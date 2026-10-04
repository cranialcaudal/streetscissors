defmodule WebWeb.LettersLive do
  @moduledoc """
  The foot of a post, a log or a frame: letters its author chose to publish,
  and a way to write one (`Web.Letters`).

  Rendered with `live_render/3` by each host page, with a session of:

    * `"piece"` — the `Web.Pieces` ref the letters belong to
    * `"remote_ip"` — captured by the host, because a nested LiveView cannot
      read connect_info itself; the session is signed, so it cannot be
      forged to dodge the rate limit

  The frame view patches between frames, so it keys this view's `id` by the
  frame (`"letters-frame-013-4"`): a new id is a fresh mount for the new
  piece, where a fixed one would keep showing the first frame's letters.

  The form is a `<details>`, closed until someone means to write, with the
  captcha and a per-IP limit of three letters an hour — the guestbook's
  guard. A nested view has no layout of its own, so its notices are said in
  place rather than through the flash.
  """

  use WebWeb, :live_view

  alias Web.Letters

  def mount(_params, session, socket) do
    piece = session["piece"]
    captcha = WebWeb.Captcha.new()

    {:ok,
     socket
     |> assign(
       piece: piece,
       remote_ip: session["remote_ip"] || "unknown",
       letters: Letters.list_published(piece),
       citations: Web.Webmentions.list_approved(piece),
       form: to_form(Letters.change_letter(piece), as: :letter),
       captcha_question: captcha.question,
       captcha_answer: captcha.answer,
       sent: false,
       error: nil
     ), layout: false}
  end

  def handle_event("validate", %{"letter" => params}, socket) do
    changeset =
      socket.assigns.piece
      |> Letters.change_letter(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :letter))}
  end

  def handle_event("send", %{"letter" => params} = all, socket) do
    cond do
      not WebWeb.Captcha.validate(all["captcha"], socket.assigns.captcha_answer) ->
        {:noreply,
         refresh_captcha(socket, "That answer to the question is not right. Try this one.")}

      rate_limited?(socket) ->
        {:noreply,
         assign(socket, error: "That is a lot of letters for one hour. Please try again later.")}

      true ->
        case Letters.create(socket.assigns.piece, params) do
          {:ok, _letter} ->
            {:noreply,
             socket
             |> assign(sent: true, error: nil)
             |> assign(form: to_form(Letters.change_letter(socket.assigns.piece), as: :letter))}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             refresh_captcha(assign(socket, form: to_form(changeset, as: :letter)), nil)}

          {:error, :unknown_piece} ->
            {:noreply, assign(socket, error: "This piece can't take letters.")}
        end
    end
  end

  def handle_event("write_another", _params, socket) do
    {:noreply, refresh_captcha(assign(socket, sent: false), nil)}
  end

  defp refresh_captcha(socket, error) do
    captcha = WebWeb.Captcha.new()

    assign(socket,
      captcha_question: captcha.question,
      captcha_answer: captcha.answer,
      error: error
    )
  end

  defp rate_limited?(socket) do
    key = "letter:#{socket.assigns.remote_ip}"
    match?({:error, :rate_limited, _}, Web.RateLimit.hit(key, limit: 3, window: :timer.hours(1)))
  end

  def render(assigns) do
    ~H"""
    <section class="letters" aria-label="Letters">
      <div :if={@letters != []} class="letters-published">
        <h2 class="letters-title">Letters</h2>
        <article :for={letter <- @letters} class="letter">
          <p class="letter-body">{letter.message}</p>
          <p class="letter-sign">
            — {letter.name},
            <time datetime={Date.to_iso8601(NaiveDateTime.to_date(letter.inserted_at))}>
              {Calendar.strftime(letter.inserted_at, "%-d %B %Y")}
            </time>
          </p>
        </article>
      </div>

      <div :if={@citations != []} class="letters-cited">
        <h2 class="letters-title">Cited by</h2>
        <ul class="letters-citations">
          <li :for={citation <- @citations}>
            <a href={citation.source} rel="nofollow ugc noopener" class="letters-citation">
              <span class="letters-citation-title">{citation.title || citation.source_host}</span>
              <span class="letters-citation-host">{citation.source_host}</span>
            </a>
          </li>
        </ul>
      </div>

      <details class="letters-write" open={@sent || @error != nil || @form.errors != []}>
        <summary class="letters-summary">Write to me about this</summary>

        <div :if={@sent} class="letters-sent" role="status">
          <p>
            Sent, and thank you. Letters are read by a person. One is published here only if you
            allowed it and I choose to.
          </p>
          <button type="button" phx-click="write_another" class="letters-link">Write another</button>
        </div>

        <.form :if={!@sent} for={@form} phx-change="validate" phx-submit="send" class="letters-form">
          <p class="letters-hint">
            A letter, not a comment: it comes to me, not to a thread. Your email is never shown.
          </p>
          <div class="letters-row">
            <.input field={@form[:name]} type="text" label="Your name" class="letters-input" required />
            <.input
              field={@form[:email]}
              type="email"
              label="Your email"
              class="letters-input"
              required
            />
          </div>
          <.input
            field={@form[:message]}
            type="textarea"
            label="The letter"
            rows="6"
            class="letters-input letters-input--prose"
            maxlength="5000"
            required
          />
          <.input
            field={@form[:may_publish]}
            type="checkbox"
            label="You may publish this beneath the piece"
          />
          <label class="letters-captcha">
            <span class="label">{@captcha_question}</span>
            <input type="text" name="captcha" class="letters-input" autocomplete="off" required />
          </label>
          <p :if={@error} class="letters-error" role="alert">{@error}</p>
          <button type="submit" class="letters-send">Send the letter</button>
        </.form>
      </details>
    </section>
    """
  end
end
