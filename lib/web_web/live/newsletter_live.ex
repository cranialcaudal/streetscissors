defmodule WebWeb.NewsletterLive do
  use WebWeb, :live_view
  alias Web.Contact
  alias Web.Contact.Message

  def mount(_params, _session, socket) do
    changeset = Contact.change_message(%Message{})
    captcha = WebWeb.Captcha.new()

    {:ok,
     assign(socket,
       page_title: "Newsletter",
       newsletter_form: to_form(%{"email" => ""}),
       contact_form: to_form(changeset),
       # connect_info is readable only during mount, so the rate limiter's key
       # has to be captured here rather than looked up per event.
       remote_ip: WebWeb.ClientIP.from_socket(socket),
       captcha_question: captcha.question,
       captcha_answer: captcha.answer,
       grammar_matches: nil,
       newsletter_subscribed: false,
       contact_sent: false,
       error_message: nil,
       active_tab: :newsletter,
       open: true
     )}
  end

  def handle_params(_params, _url, socket) do
    tab = if Map.get(socket.assigns, :live_action) == :contact, do: :contact, else: :newsletter
    {:noreply, assign(socket, active_tab: tab)}
  end

  def handle_event("reopen", %{"tab" => tab}, socket) do
    tab = if tab == "contact", do: :contact, else: :newsletter
    {:noreply, assign(socket, open: true, active_tab: tab)}
  end

  def handle_event(event, params, socket),
    do: WebWeb.NewsletterOverlayLive.handle_event(event, params, socket)

  # The page behind the panel. The panel opens over it on arrival, as it
  # does everywhere, and closing it used to leave nothing at all: now there
  # is a page that says what this is and opens the panel again.
  def render(assigns) do
    ~H"""
    <main class="newsletter-page">
      <h1 class="newsletter-title">Newsletter</h1>
      <p class="newsletter-kicker">Dispatch</p>
      <p class="newsletter-lede">
        An occasional letter when something new is up: writing, photographs, recordings.
        Or write to me directly.
      </p>
      <p class="newsletter-ways">
        <button type="button" phx-click="reopen" phx-value-tab="newsletter" class="newsletter-way">
          Subscribe
        </button>
        <button type="button" phx-click="reopen" phx-value-tab="contact" class="newsletter-way">
          Write to me
        </button>
      </p>
    </main>
    {WebWeb.NewsletterOverlayLive.render(assigns)}
    """
  end
end
