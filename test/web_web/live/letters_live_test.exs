defmodule WebWeb.LettersLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Letters

  @piece "post:keyworded-post"

  defp mount_letters(conn, ip \\ nil) do
    ip = ip || "203.0.113.#{System.unique_integer([:positive]) |> rem(250)}"
    live_isolated(conn, WebWeb.LettersLive, session: %{"piece" => @piece, "remote_ip" => ip})
  end

  defp captcha_answer(view), do: :sys.get_state(view.pid).socket.assigns.captcha_answer

  defp write(view, captcha, extra \\ %{}) do
    view
    |> form(".letters-form", %{
      "letter" =>
        Map.merge(
          %{"name" => "Ada", "email" => "ada@example.com", "message" => "Dear you,"},
          extra
        ),
      "captcha" => captcha
    })
    |> render_submit()
  end

  test "published letters show beneath the piece; private ones never do", %{conn: conn} do
    {:ok, shown} =
      Letters.create(@piece, %{
        "name" => "Shown",
        "email" => "s@example.com",
        "message" => "Public words.",
        "may_publish" => "true"
      })

    {:ok, _} = Letters.publish(shown)

    Letters.create(@piece, %{
      "name" => "Hidden",
      "email" => "h@example.com",
      "message" => "Private words."
    })

    {:ok, _view, html} = mount_letters(conn)
    assert html =~ "Public words."
    refute html =~ "Private words."
    refute html =~ "s@example.com"
  end

  test "a wrong answer to the question sends nothing", %{conn: conn} do
    {:ok, view, _html} = mount_letters(conn)
    html = write(view, "definitely wrong")

    assert html =~ "not right"
    assert Web.Contact.list_messages() == []
  end

  test "a letter is sent with its piece and the writer's consent", %{conn: conn} do
    {:ok, view, _html} = mount_letters(conn)
    html = write(view, captcha_answer(view), %{"may_publish" => "true"})

    assert html =~ "Sent, and thank you"
    assert [letter] = Web.Contact.list_messages()
    assert letter.piece == @piece
    assert letter.may_publish
    assert is_nil(letter.published_at)
  end

  test "three letters an hour from one address, then no more", %{conn: conn} do
    ip = "198.51.100.#{System.unique_integer([:positive]) |> rem(250)}"

    for _ <- 1..3 do
      {:ok, view, _} = mount_letters(conn, ip)
      write(view, captcha_answer(view))
    end

    {:ok, view, _} = mount_letters(conn, ip)
    assert write(view, captcha_answer(view)) =~ "a lot of letters"
    assert length(Web.Contact.list_messages()) == 3
  end

  test "posts, logs and frames each carry the letters", %{conn: conn} do
    assert conn |> get("/blog/keyworded-post") |> html_response(200) =~ "Write to me about this"

    log = log_fixture(%{recorded_on: ~D[2026-07-20]})
    {:ok, view, _html} = live(conn, "/logs/#{log.slug}")
    assert find_live_child(view, "letters-log-#{log.slug}")

    {:ok, view, _html} = live(conn, "/negatives/roll/001/frame/1")
    assert find_live_child(view, "letters-frame-001-1")
  end
end
