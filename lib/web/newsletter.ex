defmodule Web.Newsletter do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Newsletter.Subscriber

  alias Web.Email
  alias Web.Mailer

  def subscribe(email) do
    result =
      %Subscriber{}
      |> Subscriber.changeset(%{email: email})
      |> Repo.insert()

    case result do
      {:ok, subscriber} ->
        Email.welcome(subscriber.email) |> Mailer.deliver()
        {:ok, subscriber}

      error ->
        error
    end
  end

  def unsubscribe(email) do
    from(s in Subscriber, where: s.email == ^email)
    |> Repo.delete_all()
  end

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
