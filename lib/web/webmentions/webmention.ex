defmodule Web.Webmentions.Webmention do
  @moduledoc "A received webmention: `source` links to `target`, which is one of our pieces."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending held approved rejected gone)

  schema "webmentions" do
    field :source, :string
    field :target, :string
    field :piece, :string
    field :status, :string, default: "pending"
    field :title, :string
    field :author_name, :string
    field :source_host, :string
    field :verified_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [
      :source,
      :target,
      :piece,
      :status,
      :title,
      :author_name,
      :source_host,
      :verified_at
    ])
    |> validate_required([:source, :target, :piece, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:source, max: 2000)
    |> validate_length(:target, max: 2000)
    |> update_change(:title, &truncate(&1, 250))
    |> update_change(:author_name, &truncate(&1, 120))
    |> unique_constraint([:source, :target])
  end

  defp truncate(nil, _), do: nil
  defp truncate(value, max), do: String.slice(value, 0, max)
end
