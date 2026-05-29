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
  Creates or updates a setting.
  """
  def put_setting(key, value) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key, value: value})
        |> Repo.insert()

      %Setting{} = setting ->
        setting
        |> Setting.changeset(%{value: value})
        |> Repo.update()
    end
  end

  @doc """
  Returns a map of all settings.
  """
  def get_all_settings do
    Repo.all(Setting)
    |> Enum.into(%{}, fn s -> {s.key, s.value} end)
  end
end
