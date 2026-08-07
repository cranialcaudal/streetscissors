defmodule Web.Newsletter.Subscriber do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscribers" do
    field :email, :string
    field :active, :boolean, default: true
    field :unsubscribe_token, :string
    timestamps()
  end

  def changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [:email, :active])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> put_unsubscribe_token()
    |> unique_constraint(:email)
    |> unique_constraint(:unsubscribe_token)
  end

  # Assigned once and never regenerated: the link has to keep working out of a
  # mail archive years later, including across secret rotations and restarts.
  # Deliberately not derived from the address — the token must not leak who it
  # belongs to, or the endpoint becomes a way to unsubscribe anyone.
  defp put_unsubscribe_token(changeset) do
    case get_field(changeset, :unsubscribe_token) do
      nil -> put_change(changeset, :unsubscribe_token, generate_token())
      _ -> changeset
    end
  end

  @doc "A fresh opaque token. 24 random bytes, URL-safe."
  def generate_token, do: 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
