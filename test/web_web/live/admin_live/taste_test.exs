defmodule WebWeb.AdminLive.TasteTest do
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Web.NegativesFixtures

  alias Web.Darkroom.Taste

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are sent away", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/darkroom/taste")
  end

  # The pair is drawn from prints the measuring can read: real pictures.
  if System.find_executable("magick") do
    setup do
      root = archive!()
      folder = put_roll!(root, roll: "065", format: "35mm", color: "color")
      put_sheet!(root, "roll065_2026-01-01_35mm_color", 300, 200)
      File.mkdir_p!(Path.join(folder, "frames"))
      print = Path.join([folder, "frames", "06.png"])

      {_, 0} =
        System.cmd("magick", ["-size", "32x24", "gradient:rgb(200,150,120)-rgb(60,80,110)", print])

      :ok
    end

    test "two grades of a print are shown, and the one chosen is kept", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/taste")
      assert render(view) =~ "0 choices so far"

      render_async(view)
      wait_until(view, ~s(img[alt="The second grade"]))
      assert has_element?(view, ~s(img[alt="The first grade"]))

      view |> element(~s(button[phx-value-side="left"])) |> render_click()
      assert render(view) =~ "1 choices so far"

      assert [%{"roll" => "065", "frame" => 6, "chosen" => chosen, "other" => other}] =
               Taste.choices()

      assert chosen != other
    end

    test "the arrow keys choose and pass", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/taste")
      render_async(view)
      wait_until(view, ~s(img[alt="The second grade"]))

      render_keydown(view, "key", %{"key" => "ArrowDown"})
      assert Taste.choices() == []

      render_async(view)
      wait_until(view, ~s(img[alt="The second grade"]))
      render_keydown(view, "key", %{"key" => "ArrowRight"})
      assert length(Taste.choices()) == 1
    end
  end

  defp wait_until(view, selector, tries \\ 100) do
    cond do
      has_element?(view, selector) -> :ok
      tries == 0 -> flunk("#{selector} never appeared: #{render(view)}")
      true -> Process.sleep(20) && wait_until(view, selector, tries - 1)
    end
  end
end
