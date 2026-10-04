defmodule Web.Webmentions.Sent do
  @moduledoc "A webmention sent: our `source` page links to their `target`."

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(queued sent no_endpoint failed withdrawn)

  schema "webmentions_sent" do
    field :source, :string
    field :target, :string
    field :endpoint, :string
    field :status, :string, default: "queued"
    field :detail, :string
    field :sent_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(sent, attrs) do
    sent
    |> cast(attrs, [:source, :target, :endpoint, :status, :detail, :sent_at])
    |> validate_required([:source, :target, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:target, max: 2000)
    |> update_change(:detail, &truncate/1)
    |> unique_constraint([:source, :target])
  end

  defp truncate(nil), do: nil
  defp truncate(detail), do: String.slice(detail, 0, 250)
end
