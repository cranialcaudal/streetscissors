defmodule WebWeb.AdminLive.NewsletterTest do
  use WebWeb.ConnCase
  use Oban.Testing, repo: Web.Repo
  import Phoenix.LiveViewTest

  alias Web.Newsletter
  alias Web.Newsletter.Subscriber
  alias Web.Repo

  test "admin can broadcast newsletter to subscribers via Oban", %{conn: conn} do
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

    # Check for success flash
    assert render(view) =~ "Queued 2 subscribers for delivery"

    # A job was enqueued per subscriber, staggered rather than sent inline
    assert_enqueued(worker: Web.Workers.NewsletterSender, args: %{"email" => "sub1@example.com"})
    assert_enqueued(worker: Web.Workers.NewsletterSender, args: %{"email" => "sub2@example.com"})

    # Draining runs the jobs now, as if their scheduled_at had already elapsed
    Oban.drain_queue(queue: :mailers, with_scheduled: true)

    assert_email_sent(subject: "Big News", to: "sub1@example.com")
    assert_email_sent(subject: "Big News", to: "sub2@example.com")

    # The broadcast is recorded so past sends stay visible
    assert [sent] = Newsletter.list_sent()
    assert sent.subject == "Big News"
    assert sent.recipient_count == 2
    assert render(view) =~ "Big News"
    assert render(view) =~ "2 sent"
  end
end
