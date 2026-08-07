defmodule WebWeb.AdminLive.NewsletterTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Newsletter.Subscriber
  alias Web.Repo

  test "admin can broadcast newsletter to subscribers", %{conn: conn} do
    # Seed subscribers directly to avoid welcome emails
    Repo.insert!(%Subscriber{email: "sub1@example.com", active: true})
    Repo.insert!(%Subscriber{email: "sub2@example.com", active: true})

    # Cheat auth
    conn = init_test_session(conn, %{"admin_user" => "true"})

    {:ok, view, _html} = live(conn, "/admin/newsletter")

    # Fill and send form
    view
    |> form("#newsletter-form", %{"subject" => "Big News", "body" => "<p>Hello world</p>"})
    |> render_submit()

    # Wait for the async task to finish by monitoring its PID
    for pid <- Task.Supervisor.children(Web.TaskSupervisor) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000
    end

    # Check for success flash
    assert render(view) =~ "Broadcasting to 2 subscribers in the background"

    # Verify emails sent
    assert_email_sent(subject: "Big News", to: "sub1@example.com")
    assert_email_sent(subject: "Big News", to: "sub2@example.com")
  end
end
