defmodule Web.Newsletter do
  import Ecto.Query, warn: false
  alias Web.Repo
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

  def list_drafts do
    Repo.all(from d in Web.Newsletter.Draft, order_by: [desc: d.inserted_at])
  end
end
