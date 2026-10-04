defmodule Web.Newsletter do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Newsletter.Draft
  alias Web.Newsletter.Subscriber

  alias Web.Email
  alias Web.Mailer

  @doc """
  Subscribes an address, or brings a previously unsubscribed one back.

  Someone who unsubscribes keeps their row (see `unsubscribe/1`), so a plain
  insert would fail the unique constraint and tell a returning reader their
  address "has already been taken" — which is both wrong and unhelpful.
  """
  def subscribe(email) do
    case Repo.get_by(Subscriber, email: email) do
      %Subscriber{active: true} = existing ->
        # Already on the list. Surface it as a changeset error, as before.
        existing
        |> Subscriber.changeset(%{email: email})
        |> Ecto.Changeset.add_error(:email, "has already been taken")
        |> Ecto.Changeset.apply_action(:insert)

      %Subscriber{} = returning ->
        with {:ok, subscriber} <- reactivate(returning) do
          Email.welcome(subscriber.email) |> Mailer.deliver()
          {:ok, subscriber}
        end

      nil ->
        with {:ok, subscriber} <-
               %Subscriber{} |> Subscriber.changeset(%{email: email}) |> Repo.insert() do
          Email.welcome(subscriber.email) |> Mailer.deliver()
          {:ok, subscriber}
        end
    end
  end

  defp reactivate(subscriber) do
    subscriber |> Subscriber.changeset(%{active: true}) |> Repo.update()
  end

  @doc """
  Unsubscribes an address.

  Deactivates rather than deletes: a suppression record is the point. Deleting
  the row would let the same address be added again and mailed again, which is
  exactly what an unsubscribe is supposed to prevent. `list_active_emails/0`
  already filters on `active`, so nothing further is sent either way.

  Idempotent, and quiet about unknown addresses — an unsubscribe endpoint must
  not double as a way to test whether someone is on the list.
  """
  def unsubscribe(email) do
    case Repo.get_by(Subscriber, email: email) do
      %Subscriber{} = subscriber ->
        subscriber |> Subscriber.changeset(%{active: false}) |> Repo.update()

      nil ->
        {:ok, :not_subscribed}
    end
  end

  @doc "True when the address is on the list and still receiving."
  def subscribed?(email) do
    Repo.exists?(from s in Subscriber, where: s.email == ^email and s.active == true)
  end

  @doc "The subscriber row for an address, active or not."
  def get_subscriber(email), do: Repo.get_by(Subscriber, email: email)

  @doc "Removes a subscriber outright. Distinct from unsubscribe/1, which suppresses instead."
  def delete_subscriber(%Subscriber{} = subscriber), do: Repo.delete(subscriber)

  @doc "Resolves an unsubscribe token to its subscriber, or nil."
  def get_by_unsubscribe_token(token) when is_binary(token) do
    Repo.get_by(Subscriber, unsubscribe_token: token)
  end

  def get_by_unsubscribe_token(_), do: nil

  def list_active_emails do
    from(s in Subscriber, where: s.active == true, select: s.email)
    |> Repo.all()
  end

  def list_subscribers do
    Repo.all(Subscriber) |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @doc """
  Logs a completed broadcast so past sends stay visible in the admin UI.

  Given the draft it was composed from, that row becomes the record of the
  send rather than leaving a stale draft beside a second, sent copy.
  """
  def record_send(subject, body, recipient_count, draft \\ nil) do
    (draft || %Draft{})
    |> Draft.changeset(%{
      subject: subject,
      body: body,
      status: "sent",
      sent_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      recipient_count: recipient_count
    })
    |> Repo.insert_or_update()
  end

  # --- Drafts ---
  #
  # `newsletter_drafts` has always had a `status`; until the admin was rebuilt
  # it only ever held "sent" rows. A draft is the same row before it goes out.

  def list_drafts do
    Repo.all(from d in Draft, where: d.status == "draft", order_by: [desc: d.updated_at])
  end

  @doc "A draft by id, or `nil` — never a row that has already been sent."
  def get_draft(id), do: Repo.get_by(Draft, id: id, status: "draft")

  @doc "Creates a draft, or updates the one given."
  def save_draft(draft \\ nil, attrs) do
    (draft || %Draft{})
    |> Draft.changeset(Map.put(attrs, "status", "draft"))
    |> Repo.insert_or_update()
  end

  def delete_draft(%Draft{status: "draft"} = draft), do: Repo.delete(draft)

  @doc """
  Sends one copy to a single address, marked `[Test]` and recorded nowhere —
  for seeing the message in a real inbox before it goes to everyone.
  """
  def send_test(address, subject, body) do
    address
    |> Email.newsletter("[Test] " <> subject, body)
    |> Mailer.deliver()
  end

  def list_sent do
    Repo.all(from d in Draft, where: d.status == "sent", order_by: [desc: d.sent_at])
  end
end
