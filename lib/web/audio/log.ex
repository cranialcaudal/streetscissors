defmodule Web.Audio.Log do
  use Ecto.Schema
  import Ecto.Changeset

  alias Web.Keywords

  @moduledoc """
  One captain's log: a spoken piece with its own address at `/logs/:slug`.

  `slug` is derived from the title on insert and then left alone, so editing
  a title never breaks a published URL. `stardate` is display flavour derived
  from `recorded_on` rather than stored input.
  """

  schema "audio_logs" do
    field :title, :string
    field :slug, :string
    field :stardate, :string
    field :file_path, :string
    field :duration, :integer
    field :description, :string
    field :keywords, :string
    field :recorded_on, :date
    field :published, :boolean, default: false

    timestamps()
  end

  @castable ~w(title slug file_path duration description keywords recorded_on published)a

  def changeset(log, attrs) do
    log
    |> cast(attrs, @castable)
    |> update_change(:title, &String.trim/1)
    |> normalize_keywords()
    |> put_slug()
    |> put_stardate()
    |> validate_required([:title, :slug, :file_path, :recorded_on])
    |> validate_number(:duration, greater_than_or_equal_to: 0)
    |> unique_constraint(:slug)
  end

  @doc """
  The log's keywords as a normalized list, ready to render as chips or match
  a filter against.
  """
  @spec keyword_list(t :: %__MODULE__{}) :: [String.t()]
  def keyword_list(%__MODULE__{keywords: keywords}), do: Keywords.parse(keywords)

  @doc """
  Star Trek-style stardate for display, derived from the recording date.
  """
  @spec stardate(Date.t()) :: String.t()
  def stardate(%Date{} = date) do
    "4#{date.year - 2000}.#{trunc(Date.day_of_year(date) * 2.7)}"
  end

  defp normalize_keywords(changeset) do
    case fetch_change(changeset, :keywords) do
      {:ok, raw} -> put_change(changeset, :keywords, raw |> Keywords.parse() |> Keywords.format())
      :error -> changeset
    end
  end

  # Derived from the title so the admin form never has to think about URLs,
  # and only when there isn't one already — a published log keeps its address
  # through later title edits.
  defp put_slug(changeset) do
    case {get_field(changeset, :slug), get_field(changeset, :title)} do
      {slug, _} when is_binary(slug) and slug != "" ->
        put_change(changeset, :slug, Keywords.slugify(slug))

      {_, title} when is_binary(title) ->
        put_change(changeset, :slug, Keywords.slugify(title))

      _ ->
        changeset
    end
  end

  defp put_stardate(changeset) do
    case get_field(changeset, :recorded_on) do
      %Date{} = date -> put_change(changeset, :stardate, stardate(date))
      _ -> changeset
    end
  end
end
