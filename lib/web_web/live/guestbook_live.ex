defmodule WebWeb.GuestbookLive do
  @moduledoc """
  The guestbook (`/guestbook`): every approved signature, newest first, and the
  form to sign. A new signature waits for the author's approval
  (`/admin/guestbook`) and appears here live when approved, for everyone with
  the page open. The form has a captcha, a rate limit, and an optional
  spelling check (which sends the text to LanguageTool only when asked).
  """

  use WebWeb, :live_view
  alias Web.Guestbook
  alias Web.Guestbook.GuestbookEntry

  def mount(_params, _session, socket) do
    if connected?(socket), do: Web.Guestbook.subscribe_guestbook()

    entries = Guestbook.list_approved_guestbook_entries()
    changeset = Guestbook.change_guestbook_entry(%GuestbookEntry{})

    ip = WebWeb.Visitor.ip(socket)
    captcha = WebWeb.Captcha.new()

    # A stream: approvals arrive live and only the new one is sent, not the
    # whole book again. `signed` says whether there is anything to show.
    {:ok,
     socket
     |> stream(:entries, entries)
     |> assign(
       signed: entries != [],
       form: to_form(changeset),
       remote_ip: ip,
       captcha_question: captcha.question,
       captcha_answer: captcha.answer,
       grammar_matches: nil
     )}
  end

  def handle_event("validate", %{"guestbook_entry" => params}, socket) do
    changeset =
      %GuestbookEntry{}
      |> Guestbook.change_guestbook_entry(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"guestbook_entry" => params} = all_params, socket) do
    cond do
      not WebWeb.Captcha.validate(all_params["captcha"], socket.assigns.captcha_answer) ->
        {:noreply, refresh_captcha(socket, "Incorrect captcha. Please try again.")}

      rate_limited?(socket, "guestbook", limit: 3, window: :timer.hours(1)) ->
        {:noreply, put_flash(socket, :error, "Too many entries. Please try again later.")}

      true ->
        save_entry(socket, params)
    end
  end

  def handle_event("dismiss_grammar", _params, socket) do
    {:noreply, assign(socket, grammar_matches: nil)}
  end

  # Relays visitor text to api.languagetool.org; unlimited, this makes the site
  # a free proxy to that API and gets the server's IP banned there.
  def handle_event("check_spelling", _params, socket) do
    message =
      case socket.assigns.form.source do
        %Ecto.Changeset{} = changeset -> Ecto.Changeset.get_field(changeset, :message)
        _ -> socket.assigns.form.params["message"]
      end

    cond do
      is_nil(message) or message == "" ->
        {:noreply, put_flash(socket, :error, "Please enter a message to check.")}

      rate_limited?(socket, "spellcheck", limit: 20, window: :timer.hours(1)) ->
        {:noreply, put_flash(socket, :error, "Too many checks. Please try again later.")}

      true ->
        case Web.Language.Grammar.check(message) do
          {:ok, matches} -> {:noreply, assign(socket, grammar_matches: matches)}
          _ -> {:noreply, put_flash(socket, :error, "Grammar check failed.")}
        end
    end
  end

  # Broadcast now fires on approval rather than on insert, so anything arriving
  # here has been cleared by the admin.
  def handle_info({:guestbook_entry_created, entry}, socket) do
    {:noreply, socket |> stream_insert(:entries, entry, at: 0) |> assign(signed: true)}
  end

  defp save_entry(socket, params) do
    case Guestbook.create_guestbook_entry(params, socket.assigns.remote_ip) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> refresh_captcha()
         # Entries are held for approval now, so do not promise it is live.
         |> put_flash(:info, "Signed! Your message will appear once approved.")
         |> assign(form: to_form(Guestbook.change_guestbook_entry(%GuestbookEntry{})))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp refresh_captcha(socket, flash_error \\ nil) do
    captcha = WebWeb.Captcha.new()

    socket
    |> assign(captcha_question: captcha.question, captcha_answer: captcha.answer)
    |> then(fn s -> if flash_error, do: put_flash(s, :error, flash_error), else: s end)
  end

  # remote_ip is captured in mount/3 — connect_info is unreadable after that.
  defp rate_limited?(socket, bucket, opts) do
    key = "#{bucket}:#{socket.assigns.remote_ip}"
    match?({:error, :rate_limited, _}, Web.RateLimit.hit(key, opts))
  end
end
