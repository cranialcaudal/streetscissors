defmodule Web.SiteSettings do
  @moduledoc """
  Context for managing dynamic site settings.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.SiteSettings.Setting

  @doc """
  Gets a setting value by key, returning the default if not found.
  """
  def get_setting(key, default \\ nil) do
    case Repo.get_by(Setting, key: key) do
      %Setting{value: value} -> value
      nil -> default
    end
  end

  @doc """
  Creates or updates a setting, in one statement: an insert that becomes an
  update on the key's unique index, so two writers cannot race between a read
  and a write.
  """
  def put_setting(key, value) do
    %Setting{}
    |> Setting.changeset(%{key: key, value: value})
    |> Repo.insert(
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key,
      returning: true
    )
  end

  @doc """
  Deletes a setting if it exists.
  """
  def delete_setting(key) do
    Repo.delete_all(from(s in Setting, where: s.key == ^key))
    :ok
  end
end
