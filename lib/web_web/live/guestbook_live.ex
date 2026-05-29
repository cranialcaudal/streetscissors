defmodule WebWeb.GuestbookLive do
  use WebWeb, :live_view
  alias Web.General
  alias Web.General.GuestbookEntry

  def mount(_params, _session, socket) do
    if connected?(socket), do: Web.General.subscribe_guestbook()

    entries = General.list_approved_guestbook_entries()
    changeset = General.change_guestbook_entry(%GuestbookEntry{})

    ip =
      get_connect_info(socket, :x_headers)
      |> case do
        headers when is_list(headers) ->
          Enum.find_value(headers, fn {k, v} ->
            if String.downcase(k) == "x-forwarded-for",
              do: String.split(v, ",") |> List.first() |> String.trim()
          end)

        _ ->
          nil
      end ||
        get_connect_info(socket, :peer_data)
        |> case do
          %{address: address} ->
            address
            |> :inet.ntoa()
            |> to_string()

          _ ->
            "unknown"
        end

    captcha = WebWeb.Captcha.new()

    {:ok,
     assign(socket,
       entries: entries,
       form: to_form(changeset),
       remote_ip: ip,
       admin_mode: false,
       admin_password_value: "",
       captcha_question: captcha.question,
       captcha_answer: captcha.answer,
       grammar_matches: nil
     )}
  end

  def handle_event("validate", %{"guestbook_entry" => params}, socket) do
    changeset =
      %GuestbookEntry{}
      |> General.change_guestbook_entry(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"guestbook_entry" => params} = all_params, socket) do
    user_answer = all_params["captcha"]

    if WebWeb.Captcha.validate(user_answer, socket.assigns.captcha_answer) do
      params = Map.put(params, "ip_address", socket.assigns.remote_ip)

      case General.create_guestbook_entry(params) do
        {:ok, _entry} ->
          changeset = General.change_guestbook_entry(%GuestbookEntry{})
          captcha = WebWeb.Captcha.new()

          {:noreply,
           socket
           |> put_flash(:info, "Signed! Your message is live.")
           |> assign(
             form: to_form(changeset),
             captcha_question: captcha.question,
             captcha_answer: captcha.answer
           )}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      captcha = WebWeb.Captcha.new()

      {:noreply,
       socket
       |> put_flash(:error, "Incorrect captcha. Please try again.")
       |> assign(captcha_question: captcha.question, captcha_answer: captcha.answer)}
    end
  end

  def handle_event("dismiss_grammar", _params, socket) do
    {:noreply, assign(socket, grammar_matches: nil)}
  end

  def handle_event("check_spelling", _params, socket) do
    # Extract message from the form params or changeset
    message =
      case socket.assigns.form.source do
        %Ecto.Changeset{} = changeset -> Ecto.Changeset.get_field(changeset, :message)
        _ -> socket.assigns.form.params["message"]
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

  def handle_info({:guestbook_entry_created, entry}, socket) do
    # Always prepend since we are auto-approving
    {:noreply, update(socket, :entries, fn entries -> [entry | entries] end)}
  end
end
