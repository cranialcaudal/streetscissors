defmodule Web.RidesFixtures do
  @moduledoc """
  Test helpers for the `Web.Rides` context.
  """

  @doc "A synced ride — a public road ride unless `attrs` say otherwise."
  def ride_fixture(attrs \\ %{}) do
    {:ok, ride} =
      attrs
      |> Enum.into(%{
        komoot_id: to_string(System.unique_integer([:positive])),
        name: "Evening loop",
        sport: "racebike",
        started_at: ~U[2026-07-08 18:00:00Z],
        distance_m: 40_000.0,
        duration_s: 7200,
        time_in_motion_s: 6000,
        avg_speed_mps: 40_000.0 / 6000,
        ascent_m: 800.0,
        descent_m: 790.0,
        visibility: "public"
      })
      |> Web.Rides.create_ride()

    ride
  end

  @doc """
  An Apple Health workout — by default the one recorded alongside
  `ride_fixture/1`'s ride, starting 20 s after it.
  """
  def workout_fixture(attrs \\ %{}) do
    {:ok, workout} =
      %Web.Rides.Workout{}
      |> Web.Rides.Workout.changeset(
        Enum.into(attrs, %{
          hk_id: "hk-#{System.unique_integer([:positive])}",
          activity: "Outdoor Cycling",
          started_at: ~U[2026-07-08 18:00:20Z],
          ended_at: ~U[2026-07-08 20:00:00Z],
          active_kcal: 612,
          avg_hr: 142,
          max_hr: 171,
          hr_trace: [0, 96, 600, 128, 1200, 150, 1800, 171, 2400, 140]
        })
      )
      |> Web.Repo.insert()

    workout
  end
end
