defmodule WebWeb.HealthWebhookController do
  @moduledoc """
  `POST /api/health/ingest` — Apple Health workouts, delivered as they are
  recorded by the Health Auto Export app on the phone.

  This is the automatic way in; the other is uploading Apple's own export
  from the admin (`Web.Rides.AppleHealth`). It takes the app's payload,
  `{"data": {"workouts": [...]}}`, keeps each workout's heart rate, energy
  and times (`AppleHealth.workout_attrs/1`), and ignores everything else the
  app can be set to send: the site has no use for sleep or weight, and a
  workout's `route` is a GPS track it must never hold.

  **Closed until a token exists.** The caller proves itself with
  `Authorization: Bearer <token>`, compared in constant time against the
  token made on the admin's Activities page, of which only a digest is kept
  (or against `HEALTH_WEBHOOK_TOKEN`). With neither set every request is
  refused, so the endpoint is inert on a site that has not asked for it. A
  per-address limit keeps a stranger from guessing at it.
  """

  use WebWeb, :controller

  alias Web.Rides
  alias Web.Rides.AppleHealth

  @limit 60
  @window :timer.hours(1)

  def ingest(conn, params) do
    ip = WebWeb.ClientIP.from_conn(conn)

    with {:ok, _remaining} <- Web.RateLimit.hit("health:#{ip}", limit: @limit, window: @window),
         :ok <- authorized(conn),
         {:ok, workouts} <- workouts(params) do
      attrs = for raw <- workouts, {:ok, attrs} <- [AppleHealth.workout_attrs(raw)], do: attrs
      json(conn, %{received: length(workouts), stored: Rides.store_workouts(attrs)})
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_status(429)
        |> json(%{error: "too many requests"})

      :unauthorized ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      :unreadable ->
        conn |> put_status(422) |> json(%{error: "expected {\"data\": {\"workouts\": [...]}}"})
    end
  end

  defp authorized(conn) do
    with ["Bearer " <> given] <- get_req_header(conn, "authorization"),
         true <- AppleHealth.valid_webhook_token?(given) do
      :ok
    else
      _ -> :unauthorized
    end
  end

  # An automation set to send health metrics as well still gets its workouts
  # read; the metrics are simply not looked at.
  defp workouts(%{"data" => %{"workouts" => workouts}}) when is_list(workouts),
    do: {:ok, workouts}

  defp workouts(%{"data" => %{"metrics" => _metrics}}), do: {:ok, []}
  defp workouts(_params), do: :unreadable
end
