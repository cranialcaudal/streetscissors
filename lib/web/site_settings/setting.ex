defmodule Web.SiteSettings.Setting do
  @moduledoc """
  One site setting, as a key and a value in the `site_settings` table. These are
  the settings the admin can change from `/admin/settings` without a deploy;
  `Web.SiteSettings` reads and writes them.
  """

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
