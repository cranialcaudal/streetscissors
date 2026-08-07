defmodule Web.SiteSettings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "site_settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
