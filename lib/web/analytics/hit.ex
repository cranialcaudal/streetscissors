defmodule Web.Analytics.Hit do
  @moduledoc """
  One page visit, as stored in the `analytics_hits` table: the address visited,
  the browser's user agent, and a hash of the visitor's IP address. Never the
  address itself (`Web.Analytics.hash_ip/1`), so the table can count distinct
  visitors without holding anything that names one.
  """

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
