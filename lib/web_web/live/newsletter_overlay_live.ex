defmodule WebWeb.NewsletterOverlayLive do
  @moduledoc """
  The "dispatch" panel every page carries: two tabs, one to subscribe to the
  newsletter and one to write to the author. It opens over the page and closes
  without leaving it.

  Both forms have a captcha and are rate-limited per address. A spelling and
  grammar check is offered on the message; it sends the text to LanguageTool
  (`Web.Language.Grammar`) only when the visitor presses the button. This view
  must not set a page title: it sits inside every page, and its title would
  replace theirs.
  """

  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Contact
  alias Web.Contact.Message

  def mount(_params, session, socket) do
    changeset = Contact.change_message(%Message{})
    captcha = WebWeb.Captcha.new()

    {:ok,
     assign(socket,
       newsletter_form: to_form(%{"email" => ""}),
       contact_form: to_form(changeset),
       # The rate limiter's key. This view is rendered from the root layout,
       # so the address comes from the page that drew it (Layouts'
       # overlay_session/1); connect_info, readable only during mount, is the
       # fallback.
       remote_ip: session["remote_ip"] || WebWeb.Visitor.ip(socket),
       captcha_question: captcha.question,
       captcha_answer: captcha.answer,
       grammar_matches: nil,
       newsletter_subscribed: false,
       contact_sent: false,
       error_message: nil,
       active_tab: :newsletter,
       open: false
     ), layout: false}
  end

  def handle_event("open_dispatch", _params, socket) do
    {:noreply, assign(socket, open: true)}
  end

  def handle_event("close_dispatch", _params, socket) do
    {:noreply, assign(socket, open: false)}
  end

  # This overlay is live_rendered into the root layout, so the event is
  # reachable from every page on the site. Match the two known tabs rather than
  # String.to_existing_atom/1, which raised on any other value.
  def handle_event("switch_tab", %{"tab" => "newsletter"}, socket) do
    {:noreply, assign(socket, active_tab: :newsletter)}
  end

  def handle_event("switch_tab", %{"tab" => "contact"}, socket) do
    {:noreply, assign(socket, active_tab: :contact)}
  end

  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}

  # Newsletter Events
  def handle_event("validate_newsletter", %{"email" => email}, socket) do
    {:noreply, assign(socket, newsletter_form: to_form(%{"email" => email}))}
  end

  # Every accepted subscribe sends a real welcome email from the site's own
  # sender identity, so an unguarded loop over throwaway addresses is a direct
  # route to a blocked domain. Captcha + per-IP limit before we touch the DB.
  def handle_event("subscribe", %{"email" => email} = params, socket) do
    cond do
      not WebWeb.Captcha.validate(params["captcha"], socket.assigns.captcha_answer) ->
        {:noreply, refresh_captcha(socket, "Incorrect captcha. Please try again.")}

      rate_limited?(socket, "subscribe", limit: 3, window: :timer.hours(1)) ->
        {:noreply, assign(socket, error_message: "Too many attempts. Please try again later.")}

      true ->
        case Newsletter.subscribe(email) do
          {:ok, _subscriber} ->
            {:noreply, assign(socket, newsletter_subscribed: true, error_message: nil)}

          {:error, changeset} ->
            error_msg =
              Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
              |> Enum.map(fn {k, v} -> "#{k} #{v}" end)
              |> Enum.join(", ")

            {:noreply, socket |> refresh_captcha() |> assign(error_message: error_msg)}
        end
    end
  end

  # Contact Events
  def handle_event("validate_contact", %{"message" => params}, socket) do
    changeset =
      %Message{}
      |> Contact.change_message(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, contact_form: to_form(changeset))}
  end

  def handle_event("save_contact", %{"message" => params, "captcha" => user_answer}, socket) do
    cond do
      not WebWeb.Captcha.validate(user_answer, socket.assigns.captcha_answer) ->
        {:noreply, refresh_captcha(socket, "Incorrect captcha. Please try again.")}

      rate_limited?(socket, "contact", limit: 5, window: :timer.hours(1)) ->
        {:noreply, put_flash(socket, :error, "Too many messages. Please try again later.")}

      true ->
        save_contact_message(socket, params)
    end
  end

  # Relays arbitrary visitor text to api.languagetool.org, and this overlay is
  # rendered on every page — without a limit the site is a free open proxy to
  # that API, which gets the server's IP banned there.
  def handle_event("check_spelling", _params, socket) do
    message =
      case socket.assigns.contact_form.source do
        %Ecto.Changeset{} = changeset -> Ecto.Changeset.get_field(changeset, :message)
        _ -> socket.assigns.contact_form.params["message"]
      end

    cond do
      is_nil(message) or message == "" ->
        {:noreply, put_flash(socket, :error, "Please enter a message to check.")}

      rate_limited?(socket, "spellcheck", limit: 20, window: :timer.hours(1)) ->
        {:noreply, put_flash(socket, :error, "Too many checks. Please try again later.")}

      true ->
        case Web.Language.Grammar.check(message) do
          {:ok, matches} ->
            {:noreply, assign(socket, grammar_matches: matches)}

          _ ->
            {:noreply, put_flash(socket, :error, "Grammar check failed.")}
        end
    end
  end

  def handle_event("dismiss_grammar", _params, socket) do
    {:noreply, assign(socket, grammar_matches: nil)}
  end

  defp save_contact_message(socket, params) do
    case Contact.create_message(params) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> refresh_captcha()
         |> assign(
           contact_form: to_form(Contact.change_message(%Message{})),
           grammar_matches: nil,
           contact_sent: true
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, contact_form: to_form(changeset))}
    end
  end

  # Regenerating on every attempt means a solved answer can never be replayed.
  defp refresh_captcha(socket, flash_error \\ nil) do
    captcha = WebWeb.Captcha.new()

    socket
    |> assign(captcha_question: captcha.question, captcha_answer: captcha.answer)
    |> then(fn s -> if flash_error, do: put_flash(s, :error, flash_error), else: s end)
  end

  defp rate_limited?(socket, bucket, opts) do
    key = "#{bucket}:#{socket.assigns.remote_ip}"
    match?({:error, :rate_limited, _}, Web.RateLimit.hit(key, opts))
  end

  def render(assigns) do
    assigns = assign(assigns, :contact_email, Application.get_env(:web, :contact_email))

    ~H"""
    <div id={"#{@socket.id}-container"} phx-hook=".DispatchOverlay">
      <.dialog
        :if={@open}
        id={"#{@socket.id}-overlay"}
        class="dispatch-overlay"
        label="Newsletter and contact"
        on_close="close_dispatch"
      >
        <div class="dispatch-head">
          <h2 class="dispatch-title">Dispatch Center</h2>
          <div class="dispatch-tabs" role="tablist" aria-label="Newsletter or contact">
            <button
              :for={{tab, label} <- [newsletter: "Newsletter", contact: "Contact"]}
              type="button"
              role="tab"
              aria-selected={to_string(@active_tab == tab)}
              phx-click="switch_tab"
              phx-value-tab={tab}
              class="dispatch-tab"
            >
              {label}
            </button>
          </div>
        </div>

        <%!-- This overlay is its own LiveView, rendered with no layout, so no
              flash group exists to say what it puts: a wrong captcha or a
              rate limit was set here and shown nowhere. On /newsletter and
              /contact the dialog also covers the page's group. --%>
        <div class="flash-inline" aria-live="polite">
          <.flash kind={:error} flash={@flash} id={"#{@socket.id}-flash-error"} />
          <.flash kind={:info} flash={@flash} id={"#{@socket.id}-flash-info"} />
        </div>

        <div class="dispatch-content" role="tabpanel">
          <%= if @active_tab == :newsletter do %>
            <div :if={@newsletter_subscribed} class="dispatch-done">
              <div class="dispatch-done-mark"><.icon name="hero-check" class="size-10" /></div>
              <h2 class="dispatch-done-title">CONFIRMED</h2>
              <p class="dispatch-done-line">YOU ARE ON THE LIST</p>
            </div>

            <div :if={!@newsletter_subscribed}>
              <p class="dispatch-lede">Subscribe for updates on new logs and photographs.</p>

              <.form
                for={@newsletter_form}
                phx-change="validate_newsletter"
                phx-submit="subscribe"
                class="dispatch-form"
              >
                <div>
                  <label for={"#{@socket.id}-email"} class="dispatch-label dispatch-label--center">
                    Your email
                  </label>
                  <input
                    id={"#{@socket.id}-email"}
                    name="email"
                    type="email"
                    value={@newsletter_form[:email].value}
                    autocomplete="email"
                    required
                    class="dispatch-input dispatch-input--center"
                  />
                  <p :if={@error_message} class="dispatch-error">{@error_message}</p>
                </div>

                <%!-- Subscribing sends a real email from our own sender
                      identity, so this form gets the same human check the
                      contact tab has always had. --%>
                <div>
                  <label for={"#{@socket.id}-captcha-n"} class="dispatch-label dispatch-label--center">
                    {@captcha_question}
                  </label>
                  <input
                    id={"#{@socket.id}-captcha-n"}
                    type="text"
                    name="captcha"
                    required
                    autocomplete="off"
                    class="dispatch-input dispatch-input--center"
                  />
                </div>

                <button type="submit" class="dispatch-submit">Join the Dispatch</button>
              </.form>
            </div>
          <% else %>
            <div :if={@contact_sent} class="dispatch-done">
              <h2 class="dispatch-done-title dispatch-done-title--loud">boom.. sent</h2>
              <p class="dispatch-done-line">Message received loud and clear.</p>
              <button type="button" phx-click="switch_tab" phx-value-tab="contact" class="dispatch-again">
                Send Another?
              </button>
            </div>

            <.form
              :if={!@contact_sent}
              for={@contact_form}
              phx-change="validate_contact"
              phx-submit="save_contact"
              class="dispatch-form"
            >
              <div class="dispatch-row">
                <div>
                  <label for={"#{@socket.id}-name"} class="dispatch-label">Name</label>
                  <input
                    id={"#{@socket.id}-name"}
                    name="message[name]"
                    type="text"
                    value={@contact_form[:name].value}
                    autocomplete="name"
                    required
                    class="dispatch-input"
                  />
                </div>
                <div>
                  <label for={"#{@socket.id}-from"} class="dispatch-label">Email</label>
                  <input
                    id={"#{@socket.id}-from"}
                    name="message[email]"
                    type="email"
                    value={@contact_form[:email].value}
                    autocomplete="email"
                    required
                    class="dispatch-input"
                  />
                </div>
              </div>

              <div class="dispatch-message">
                <label for={"#{@socket.id}-message"} class="dispatch-label">Your message</label>
                <textarea
                  id={"#{@socket.id}-message"}
                  name="message[message]"
                  required
                  class="dispatch-input dispatch-input--message"
                ><%= @contact_form[:message].value %></textarea>
                <div class="dispatch-message-tools">
                  <WebWeb.CoreComponents.grammar_button class="btn-xs" />
                </div>
              </div>

              <div class="dispatch-captcha">
                <label for={"#{@socket.id}-captcha-c"} class="dispatch-label">
                  CAPTCHA: {@captcha_question}
                </label>
                <input
                  id={"#{@socket.id}-captcha-c"}
                  name="captcha"
                  type="text"
                  required
                  autocomplete="off"
                  class="dispatch-input"
                />
              </div>

              <button type="submit" class="dispatch-submit">Send Message</button>
            </.form>
          <% end %>
        </div>

        <div :if={@contact_email} class="dispatch-foot">
          <a href={"mailto:#{@contact_email}"} class="dispatch-footer-link">
            {String.upcase(@contact_email)}
          </a>
        </div>

        <div class="dispatch-grammar">
          <WebWeb.CoreComponents.grammar_panel matches={@grammar_matches} />
        </div>
      </.dialog>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".DispatchOverlay">
        // Any "Newsletter & Contact" button on any page (data-dispatch, wired
        // in app.js) asks this overlay to open. The listener is removed with
        // the hook, so a remount does not open it twice.
        export default {
          mounted() {
            this.open = () => this.pushEvent("open_dispatch", {})
            window.addEventListener("trigger-dispatch", this.open)
          },
          destroyed() {
            window.removeEventListener("trigger-dispatch", this.open)
          }
        }
      </script>
    </div>
    """
  end
end
