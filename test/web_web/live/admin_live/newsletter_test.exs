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

  describe "composing" do
    setup %{conn: conn} do
      {:ok, conn: init_test_session(conn, %{"admin_user" => "true"})}
    end

    test "the preview shows the message inside the email's own shell", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/newsletter")

      view
      |> form("#newsletter-form", %{"subject" => "Hi", "body" => "<p>Ferry at dawn</p>"})
      |> render_change()

      srcdoc = view |> element("#newsletter-preview") |> render()
      assert srcdoc =~ "Ferry at dawn"
      assert srcdoc =~ "Unsubscribe"
    end

    test "a draft is saved, reopened, and becomes the record of its send", %{conn: conn} do
      Repo.insert!(%Subscriber{email: "sub1@example.com", active: true})
      {:ok, view, _html} = live(conn, "/admin/newsletter")

      view
      |> form("#newsletter-form", %{"subject" => "Draft One", "body" => "<p>Not yet</p>"})
      |> render_change()

      view |> element("button[phx-click=save_draft]") |> render_click()
      assert [draft] = Newsletter.list_drafts()
      assert draft.subject == "Draft One"

      # A fresh page, then the draft is picked back up from the list.
      {:ok, view, _html} = live(conn, "/admin/newsletter")

      view
      |> element(~s(button[phx-click=open_draft][phx-value-id="#{draft.id}"]))
      |> render_click()

      assert view |> element("#newsletter-form input[name=subject]") |> render() =~ "Draft One"

      view
      |> form("#newsletter-form", %{"subject" => "Draft One", "body" => "<p>Now</p>"})
      |> render_submit()

      assert Newsletter.list_drafts() == []
      assert [sent] = Newsletter.list_sent()
      assert sent.id == draft.id
      assert sent.body == "<p>Now</p>"
    end

    test "a test goes to one address, marked, and is recorded nowhere", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/newsletter")

      view
      |> form("#newsletter-form", %{"subject" => "Big News", "body" => "<p>Hello</p>"})
      |> render_change()

      view
      |> form("#newsletter-test-form", %{"test_email" => "me@example.com"})
      |> render_submit()

      assert_email_sent(subject: "[Test] Big News", to: "me@example.com")
      assert Newsletter.list_sent() == []
      assert render(view) =~ "Test sent to me@example.com."
    end

    test "a test with nothing written is refused", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/newsletter")

      view
      |> form("#newsletter-test-form", %{"test_email" => "me@example.com"})
      |> render_submit()

      assert_no_email_sent()
      assert render(view) =~ "Write a subject and a body"
    end

    test "a subscriber can be removed from the list", %{conn: conn} do
      sub = Repo.insert!(%Subscriber{email: "gone@example.com", active: true})

      {:ok, view, html} = live(conn, "/admin/newsletter")
      assert html =~ "gone@example.com"

      view
      |> element("button[phx-click='delete_subscriber'][phx-value-id='#{sub.id}']")
      |> render_click()

      refute render(view) =~ "gone@example.com"
      refute Repo.get(Subscriber, sub.id)
    end
  end
end
