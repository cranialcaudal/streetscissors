defmodule Web.Analytics.Hit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "analytics_hits" do
    field :path, :string
    field :user_agent, :string
    field :ip_hash, :string
    timestamps(updated_at: false)
  end

  def changeset(hit, attrs) do
    hit
    |> cast(attrs, [:path, :user_agent, :ip_hash])
    |> validate_required([:path])
  end
end
