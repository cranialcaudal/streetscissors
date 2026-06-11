defmodule Web.Komoot.Client do
  @moduledoc """
  Thin client for Komoot's unofficial API (the one the mobile apps use,
  reverse-engineered by tools like KomootGPX). It can disappear or change
  without notice, so callers must treat every function as fallible and the
  manual GPX import remains the permanent fallback.

  Auth flow: a basic-auth GET with the account email + password returns the
  numeric user id and an API token; all further calls use basic auth with
  `{user_id, token}`.
  """

  @base_url "https://api.komoot.de"

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
  All tours of the given type — `"tour_recorded"` or `"tour_planned"` —
  following pagination to the end.
  """
  @spec list_tours(auth, String.t()) :: {:ok, [map]} | {:error, term}
  def list_tours(auth, type) when type in ~w(tour_recorded tour_planned) do
    list_tours_page(auth, "/v007/users/#{auth.user_id}/tours/?type=#{type}&limit=50", [])
  end

  defp list_tours_page(auth, url, acc) do
    case Req.get(req(), url: url, auth: basic(auth)) do
      {:ok, %{status: 200, body: body}} ->
        tours = get_in(body, ["_embedded", "tours"]) || []
        acc = acc ++ tours

        case get_in(body, ["_links", "next", "href"]) do
          nil -> {:ok, acc}
          next -> list_tours_page(auth, next, acc)
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "The full coordinate track of a tour: `[%{\"lat\", \"lng\", \"alt\", \"t\"}]`."
  @spec fetch_coordinates(auth, term) :: {:ok, [map]} | {:error, term}
  def fetch_coordinates(auth, tour_id) do
    case Req.get(req(), url: "/v007/tours/#{tour_id}?_embedded=coordinates", auth: basic(auth)) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, get_in(body, ["_embedded", "coordinates", "items"]) || []}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp basic(%{user_id: user_id, token: token}), do: {:basic, "#{user_id}:#{token}"}

  # retry: false — unofficial API, don't hammer it (and never retry a failed
  # login: repeated auth failures risk an account lockout).
  defp req do
    Req.new(base_url: @base_url, retry: false)
    |> Req.merge(Application.get_env(:web, :komoot_req_options, []))
  end
end
