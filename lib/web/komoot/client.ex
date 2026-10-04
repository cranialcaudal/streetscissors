defmodule Web.Komoot.Client do
  @moduledoc """
  Thin client for Komoot's unofficial API (the one the mobile apps use,
  reverse-engineered by tools like KomootGPX). It can disappear or change
  without notice, so callers must treat every function as fallible.

  Auth flow: a basic-auth GET with the account email + password returns the
  numeric user id and an API token; all further calls use basic auth with
  `{user_id, token}`.
  """

  @base_url "https://api.komoot.de"

  # One page wide enough that a normal archive never paginates. The ETag
  # short-circuit in `list_tours/3` only applies to a single-page listing,
  # so it is worth paying a slightly larger first page to stay on that path.
  @page_limit 200

  @type auth :: %{user_id: String.t(), token: String.t()}

  @spec login(String.t(), String.t()) :: {:ok, auth} | {:error, term}
  def login(email, password) do
    case Req.get(req(),
           url: "/v006/account/email/#{URI.encode(email)}/",
           auth: {:basic, "#{email}:#{password}"}
         ) do
      {:ok, %{status: 200, body: %{"username" => user_id, "password" => token}}} ->
        {:ok, %{user_id: user_id, token: token}}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :auth_failed}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  All of the user's recorded tours, following pagination to the end.

  Pass the ETag returned by an earlier call to make the request conditional.
  Komoot's ETag is a plain content hash of the listing body, so a `304` is a
  guarantee that nothing in it moved — not a tour added, renamed, re-stat'd,
  or flipped between public and private — and the caller can skip the whole
  pass without reading a byte. That is the normal outcome: an hourly sync
  against an archive that gains a tour or two a week is almost entirely
  conditional requests.

  Returns the fresh ETag alongside the tours, or `nil` when the listing
  paginated — the header covers only the first page, so caching it would
  hide a change further down.
  """
  @spec list_tours(auth, String.t() | nil) ::
          {:ok, [map], String.t() | nil} | :not_modified | {:error, term}
  def list_tours(auth, etag \\ nil) do
    url = "/v007/users/#{auth.user_id}/tours/?type=tour_recorded&limit=#{@page_limit}"

    case Req.get(req(), url: url, auth: basic(auth), headers: if_none_match(etag)) do
      {:ok, %{status: 304}} ->
        :not_modified

      {:ok, %{status: 200, body: body} = response} ->
        tours = embedded_tours(body)

        case next_href(body) do
          nil ->
            {:ok, tours, etag_of(response)}

          next ->
            with {:ok, rest} <- list_tours_page(auth, next, []) do
              {:ok, tours ++ rest, nil}
            end
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_tours_page(auth, url, acc) do
    case Req.get(req(), url: url, auth: basic(auth)) do
      {:ok, %{status: 200, body: body}} ->
        acc = acc ++ embedded_tours(body)

        case next_href(body) do
          nil -> {:ok, acc}
          next -> list_tours_page(auth, next, acc)
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp embedded_tours(body), do: get_in(body, ["_embedded", "tours"]) || []

  defp next_href(body), do: get_in(body, ["_links", "next", "href"])

  defp if_none_match(nil), do: []
  defp if_none_match(etag), do: [{"if-none-match", etag}]

  defp etag_of(%{headers: headers}) do
    case headers["etag"] do
      [etag | _] when is_binary(etag) -> etag
      _ -> nil
    end
  end

  @doc """
  The GPS track of a tour as `[{lat, lng, alt_m, t_ms}]`, in recorded order.
  Altitude and time are nil where Komoot sent none; a point without a
  position is dropped.
  """
  @spec tour_track(auth, String.t()) ::
          {:ok, [{float, float, number | nil, number | nil}]} | {:error, term}
  def tour_track(auth, tour_id) do
    case Req.get(req(), url: "/v007/tours/#{tour_id}?_embedded=coordinates", auth: basic(auth)) do
      {:ok, %{status: 200, body: %{"_embedded" => %{"coordinates" => %{"items" => items}}}}}
      when is_list(items) ->
        {:ok,
         for %{"lat" => lat, "lng" => lng} = item <- items, is_number(lat) and is_number(lng) do
           {lat / 1, lng / 1, number_or_nil(item["alt"]), number_or_nil(item["t"])}
         end}

      {:ok, %{status: 200}} ->
        {:error, :no_coordinates}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp number_or_nil(value) when is_number(value), do: value
  defp number_or_nil(_value), do: nil

  defp basic(%{user_id: user_id, token: token}), do: {:basic, "#{user_id}:#{token}"}

  # retry: false — unofficial API, don't hammer it (and never retry a failed
  # login: repeated auth failures risk an account lockout). The explicit
  # receive_timeout keeps a hung response from wedging the hourly Quantum
  # job; a pass that times out simply runs again next hour.
  defp req do
    Req.new(base_url: @base_url, retry: false, receive_timeout: 15_000)
    |> Req.merge(Application.get_env(:web, :komoot_req_options, []))
  end
end
