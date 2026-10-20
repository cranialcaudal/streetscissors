defmodule Web.Negatives.RollMetaKnownTest do
  # The archive's root is application config, so not async.
  use ExUnit.Case, async: false

  import Web.NegativesFixtures

  alias Web.Negatives.RollMeta

  defp meta(fields), do: Map.merge(%{shot: nil, camera: nil, film: nil, place: nil, notes: nil}, fields)

  test "what earlier rolls said is offered, most used first, the newest roll's as the last" do
    root = archive!()

    for {roll, fields} <- [
          {"001", %{camera: "Pentax 67", film: "Portra 400", place: "Valley"}},
          {"002", %{camera: "Pentax 67", film: "HP5"}},
          {"003", %{camera: "Olympus XA", film: "Portra 400"}}
        ] do
      folder = put_roll!(root, roll: roll)
      put_sheet!(root, "roll#{roll}_2026-01-01_120_bw", 30, 20)
      :ok = RollMeta.write(folder, meta(fields))
    end

    known = RollMeta.known()
    assert known.camera == ["Pentax 67", "Olympus XA"]
    assert known.film == ["Portra 400", "HP5"]
    assert known.place == ["Valley"]
    assert %{camera: "Olympus XA"} = known.last
  end

  test "the roll being described is left out" do
    root = archive!()
    folder = put_roll!(root, roll: "004")
    put_sheet!(root, "roll004_2026-01-01_120_bw", 30, 20)
    :ok = RollMeta.write(folder, meta(%{camera: "Mamiya 7"}))

    assert %{camera: [], last: nil} = RollMeta.known(folder)
  end
end
