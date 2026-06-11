defmodule WebWeb.NewsletterLive do
  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Contact
  alias Web.Contact.Message

  def mount(_params, _session, socket) do
    changeset = Contact.change_message(%Message{})
    captcha = WebWeb.Captcha.new()

    {:ok,
     assign(socket,
       page_title: "Dispatch",
       newsletter_form: to_form(%{"email" => ""}),
       contact_form: to_form(changeset),
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

  def handle_event(event, params, socket),
    do: WebWeb.NewsletterOverlayLive.handle_event(event, params, socket)

  def render(assigns) do
    WebWeb.NewsletterOverlayLive.render(assigns)
  end
end

defmodule WebWeb.NewsletterOverlayLive do
  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Contact
  alias Web.Contact.Message

  def mount(_params, _session, socket) do
    changeset = Contact.change_message(%Message{})
    captcha = WebWeb.Captcha.new()

    {:ok,
     assign(socket,
       page_title: "Dispatch",
       newsletter_form: to_form(%{"email" => ""}),
       contact_form: to_form(changeset),
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

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_existing_atom(tab))}
  end

  # Newsletter Events
  def handle_event("validate_newsletter", %{"email" => email}, socket) do
    {:noreply, assign(socket, newsletter_form: to_form(%{"email" => email}))}
  end

  def handle_event("subscribe", %{"email" => email}, socket) do
    case Newsletter.subscribe(email) do
      {:ok, _subscriber} ->
        {:noreply, assign(socket, newsletter_subscribed: true)}

      {:error, changeset} ->
        error_msg =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          |> Enum.map(fn {k, v} -> "#{k} #{v}" end)
          |> Enum.join(", ")

        {:noreply, assign(socket, error_message: error_msg)}
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
    if WebWeb.Captcha.validate(user_answer, socket.assigns.captcha_answer) do
      case Contact.create_message(params) do
        {:ok, _message} ->
          changeset = Contact.change_message(%Message{})
          captcha = WebWeb.Captcha.new()

          {:noreply,
           socket
           |> assign(
             contact_form: to_form(changeset),
             captcha_question: captcha.question,
             captcha_answer: captcha.answer,
             grammar_matches: nil,
             contact_sent: true
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, contact_form: to_form(changeset))}
      end
    else
      captcha = WebWeb.Captcha.new()

      {:noreply,
       socket
       |> put_flash(:error, "Incorrect captcha. Please try again.")
       |> assign(captcha_question: captcha.question, captcha_answer: captcha.answer)}
    end
  end

  def handle_event("check_spelling", _params, socket) do
    message =
      case socket.assigns.contact_form.source do
        %Ecto.Changeset{} = changeset -> Ecto.Changeset.get_field(changeset, :message)
        _ -> socket.assigns.contact_form.params["message"]
      end

    if message && message != "" do
      case Web.Language.Grammar.check(message) do
        {:ok, matches} ->
          {:noreply, assign(socket, grammar_matches: matches)}

        _ ->
          {:noreply, put_flash(socket, :error, "Grammar check failed.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter a message to check.")}
    end
  end

  def handle_event("dismiss_grammar", _params, socket) do
    {:noreply, assign(socket, grammar_matches: nil)}
  end

  def render(assigns) do
    ~H"""
    <div id={"#{@socket.id}-container"} phx-hook="DispatchOverlay">
      <%= if @open do %>
        <div
          id={"#{@socket.id}-overlay"}
          class="dispatch-overlay animate-fade-in"
          style="position: fixed; inset: 0; z-index: 100000; background: rgba(0,0,0,0.7); backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center; padding: 1rem; overflow-y: auto;"
          phx-window-keydown="close_dispatch"
          phx-key="Escape"
        >
          <div
            class="glass-panel"
            phx-click-away="close_dispatch"
            style="width: 100%; max-width: 650px; padding: 3rem; position: relative; border: 1px solid rgba(255,102,0,0.4); box-shadow: 0 20px 50px rgba(0,0,0,0.8); background: rgba(10,10,10,0.95); border-radius: 12px;"
          >
            <button
              phx-click="close_dispatch"
              class="dispatch-close"
              style="position: absolute; top: 1.2rem; right: 1.2rem; font-size: 2.5rem; color: #444; background: none; border: none; cursor: pointer; transition: all 0.2s; line-height: 1; display: flex; align-items: center; justify-content: center; width: 44px; height: 44px; border-radius: 50%; z-index: 10;"
              onmouseover="this.style.color='#ff6600'; this.style.background='rgba(255,102,0,0.1)'"
              onmouseout="this.style.color='#444'; this.style.background='transparent'"
            >
              &times;
            </button>

            <div style="margin-bottom: 3rem; text-align: center;">
              <h2 style="font-family: var(--font-heading); font-size: 1.2rem; color: #ff6600; letter-spacing: 4px; text-transform: uppercase; margin-bottom: 2rem;">
                Dispatch Center
              </h2>

              <div style="display: inline-flex; background: #000; padding: 0.5rem; border-radius: 50px; border: 1px solid #222;">
                <button
                  phx-click="switch_tab"
                  phx-value-tab="newsletter"
                  style={"padding: 0.6rem 2rem; border-radius: 40px; font-family: var(--font-heading); font-size: 1rem; border: none; cursor: pointer; transition: all 0.3s; " <> (if @active_tab == :newsletter, do: "background: #ff6600; color: black;", else: "background: transparent; color: #666;")}
                >
                  Newsletter
                </button>
                <button
                  phx-click="switch_tab"
                  phx-value-tab="contact"
                  style={"padding: 0.6rem 2rem; border-radius: 40px; font-family: var(--font-heading); font-size: 1rem; border: none; cursor: pointer; transition: all 0.3s; " <> (if @active_tab == :contact, do: "background: #ff6600; color: black;", else: "background: transparent; color: #666;")}
                >
                  Contact
                </button>
              </div>
            </div>

            <div class="dispatch-content">
              <%= if @active_tab == :newsletter do %>
                <%= if @newsletter_subscribed do %>
                  <div class="animate-fade-in" style="text-align: center; padding: 3rem 0;">
                    <div style="width: 80px; height: 80px; background: rgba(255,102,0,0.1); border-radius: 50%; display: flex; align-items: center; justify-content: center; margin: 0 auto 1.5rem; border: 1px solid #ff6600;">
                      <.icon name="hero-check" class="size-10 text-[#ff6600]" />
                    </div>
                    <h2 style="font-size: 2rem; margin-bottom: 0.5rem; color: white; font-family: var(--font-heading);">
                      CONFIRMED
                    </h2>
                    <p style="color: #666; letter-spacing: 1px;">YOU ARE ON THE LIST</p>
                  </div>
                <% else %>
                  <p style="margin-bottom: 2rem; color: #888; line-height: 1.8; text-align: center; max-width: 450px; margin-left: auto; margin-right: auto; font-style: italic;">
                    "The world is full of obvious things which nobody by any chance ever observes."
                    Subscribe for updates on new logs and photographs.
                  </p>

                  <.form
                    for={@newsletter_form}
                    phx-change="validate_newsletter"
                    phx-submit="subscribe"
                    style="display: flex; flex-direction: column; gap: 1.5rem;"
                  >
                    <div>
                      <input
                        name="email"
                        type="email"
                        value={@newsletter_form[:email].value}
                        placeholder="ENTER YOUR EMAIL"
                        required
                        style="width: 100%; background: #000; border: 1px solid #333; color: white; padding: 1.2rem; border-radius: 4px; font-size: 1rem; text-align: center; letter-spacing: 2px;"
                      />
                      <%= if @error_message do %>
                        <p style="color: #ff6b6b; font-size: 0.9rem; margin-top: 0.5rem; text-align: center;">
                          {@error_message}
                        </p>
                      <% end %>
                    </div>

                    <button
                      type="submit"
                      class="theme-btn"
                      style="width: 100%; padding: 1.2rem; justify-content: center; font-size: 1rem; border: 1px solid #ff6600; color: #ff6600; background: transparent; letter-spacing: 2px; text-transform: uppercase; font-weight: bold;"
                    >
                      Join the Dispatch
                    </button>
                  </.form>
                <% end %>
              <% else %>
                <%= if @contact_sent do %>
                  <div class="animate-fade-in" style="text-align: center; padding: 3rem 0;">
                    <h2 style="font-family: var(--font-heading); font-size: 4rem; color: #ff6600; margin-bottom: 1rem; text-transform: lowercase;">
                      boom.. sent
                    </h2>
                    <p style="font-size: 1.1rem; color: #666; letter-spacing: 1px;">
                      Message received loud and clear.
                    </p>
                    <div style="margin-top: 2rem;">
                      <button
                        phx-click="switch_tab"
                        phx-value-tab="contact"
                        style="background: transparent; border: 1px solid #333; color: #555; padding: 0.6rem 2rem; cursor: pointer; border-radius: 40px; font-size: 0.9rem;"
                      >
                        Send Another?
                      </button>
                    </div>
                  </div>
                <% else %>
                  <.form
                    for={@contact_form}
                    phx-change="validate_contact"
                    phx-submit="save_contact"
                    style="display: flex; flex-direction: column; gap: 1.5rem;"
                  >
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 1rem;">
                      <input
                        name="message[name]"
                        type="text"
                        value={@contact_form[:name].value}
                        placeholder="NAME"
                        required
                        style="width: 100%; background: #000; border: 1px solid #333; color: white; padding: 1rem; border-radius: 4px; font-size: 0.9rem;"
                      />
                      <input
                        name="message[email]"
                        type="email"
                        value={@contact_form[:email].value}
                        placeholder="EMAIL"
                        required
                        style="width: 100%; background: #000; border: 1px solid #333; color: white; padding: 1rem; border-radius: 4px; font-size: 0.9rem;"
                      />
                    </div>

                    <div style="position: relative;">
                      <textarea
                        name="message[message]"
                        placeholder="YOUR MESSAGE..."
                        required
                        style="width: 100%; background: #000; border: 1px solid #333; color: white; padding: 1rem; border-radius: 4px; min-height: 150px; font-size: 0.9rem;"
                      ><%= @contact_form[:message].value %></textarea>
                      <div style="position: absolute; bottom: 0.5rem; right: 0.5rem;">
                        <WebWeb.CoreComponents.grammar_button class="btn-xs" />
                      </div>
                    </div>

                    <div style="background: rgba(0,0,0,0.3); padding: 1.2rem; border-radius: 4px; border: 1px solid #222; display: flex; align-items: center; justify-content: space-between; gap: 1rem;">
                      <span style="color: #666; font-size: 0.9rem; white-space: nowrap;">
                        CAPTCHA: {@captcha_question}
                      </span>
                      <input
                        name="captcha"
                        type="text"
                        placeholder="ANSWER"
                        style="background: #000; border: 1px solid #333; color: white; padding: 0.5rem 1rem; border-radius: 4px; width: 100px; text-align: center;"
                        required
                        autocomplete="off"
                      />
                    </div>

                    <button
                      type="submit"
                      class="theme-btn"
                      style="width: 100%; padding: 1.2rem; justify-content: center; border: 1px solid #ff6600; color: #ff6600; background: transparent; font-weight: bold; letter-spacing: 2px; text-transform: uppercase;"
                    >
                      Send Message
                    </button>
                  </.form>
                <% end %>
              <% end %>
            </div>

            <div style="margin-top: 3rem; text-align: center; border-top: 1px solid #222; padding-top: 1.5rem;">
              <a
                href="mailto:streetscissors@gmail.com"
                style="color: #333; font-size: 0.7rem; text-decoration: none; letter-spacing: 3px; font-weight: bold;"
              >
                STREETSCISSORS@GMAIL.COM
              </a>
            </div>
          </div>
          <div style="position: fixed; bottom: 2rem; right: 2rem; z-index: 100000;">
            <WebWeb.CoreComponents.grammar_panel matches={@grammar_matches} />
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
