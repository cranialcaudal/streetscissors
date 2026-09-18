defmodule Web.Audio.Log do
  use Ecto.Schema
  import Ecto.Changeset

  alias Web.Keywords

  @moduledoc """
  One captain's log: a recording — video or audio — with its own address at
  `/logs/:slug`.

  An entry is titled by the day it was made, so `title/1` is derived rather
  than stored, and the address follows it: `2026-09-18` for the day's first
  entry, `2026-09-18-2` for the second. `seq` is what makes room for more than
  one recording in a day; `Web.Audio.create_log/1` assigns it, because counting
  the day's existing entries needs the repo and a changeset should not.

  `status` exists because an entry now outlives its own media: the row is
  written at `pending` the moment an upload lands, and only becomes `ready`
  once `Web.Media.Transcoder` has produced something playable. Nothing reaches
  the public page before then.
  """

  @kinds ~w(video audio)
  @statuses ~w(pending processing ready failed)

  schema "audio_logs" do
    # Identity — the title and the slug are both derived from these.
    field :recorded_on, :date
    field :seq, :integer, default: 1
    field :slug, :string
    field :recorded_at, :utc_datetime

    # What it is.
    field :kind, :string, default: "video"
    field :caption, :string
    field :description, :string
    field :keywords, :string
    field :published, :boolean, default: false

    # Where the media lives and what shape it is.
    field :media_dir, :string
    field :poster_path, :string
    field :duration, :integer
    field :width, :integer
    field :height, :integer
    field :size_bytes, :integer

    # The transcode. The trim and poster choices are inputs kept on the row,
    # not just form params, so a restart mid-encode can resume from the
    # database alone.
    field :status, :string, default: "pending"
    field :transcode_error, :string
    field :source_path, :string
    field :trim_start_ms, :integer
    field :trim_duration_ms, :integer
    field :poster_at_ms, :integer

    timestamps()
  end

  @castable ~w(recorded_on seq recorded_at kind caption description keywords published
               media_dir poster_path duration width height size_bytes status
               transcode_error source_path trim_start_ms trim_duration_ms
               poster_at_ms)a

  def changeset(log, attrs) do
    log
    |> cast(attrs, @castable)
    |> update_change(:caption, &String.trim/1)
    |> normalize_keywords()
    |> put_slug()
    |> validate_required([:recorded_on, :seq, :slug, :kind, :status])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:seq, greater_than: 0)
    |> validate_number(:duration, greater_than_or_equal_to: 0)
    |> validate_number(:trim_start_ms, greater_than_or_equal_to: 0)
    |> validate_number(:trim_duration_ms, greater_than: 0)
    |> unique_constraint(:slug)
    |> unique_constraint(:seq, name: :audio_logs_recorded_on_seq_index)
  end

  @doc "The kinds an entry may be."
  def kinds, do: @kinds

  @doc "The states a transcode may be in."
  def statuses, do: @statuses

  @doc """
  The entry's title: the day it was recorded, written out.

      iex> Web.Audio.Log.title(%Web.Audio.Log{recorded_on: ~D[2026-09-18]})
      "Thursday, 18 September 2026"
  """
  def title(%__MODULE__{recorded_on: %Date{} = date}),
    do: Calendar.strftime(date, "%A, %-d %B %Y")

  def title(%__MODULE__{}), do: "Undated log"

  @doc """
  The entry's mark within its day, zero-padded — or `nil` for the day's only
  (or first) entry, which needs no disambiguating.

      iex> Web.Audio.Log.ordinal(%Web.Audio.Log{seq: 1})
      nil
      iex> Web.Audio.Log.ordinal(%Web.Audio.Log{seq: 2})
      "02"
  """
  def ordinal(%__MODULE__{seq: seq}) when is_integer(seq) and seq > 1,
    do: seq |> to_string() |> String.pad_leading(2, "0")

  def ordinal(%__MODULE__{}), do: nil

  @doc "The address for a given day and ordinal: `2026-09-18`, then `2026-09-18-2`."
  def slug_for(%Date{} = date, seq) when is_integer(seq) and seq > 1,
    do: "#{Date.to_iso8601(date)}-#{seq}"

  def slug_for(%Date{} = date, _seq), do: Date.to_iso8601(date)

  @doc """
  Where this entry's media is played from, or `nil` while there is nothing to
  play — a caller can render a poster and a disabled control off that `nil`
  rather than pointing a player at a path that does not exist yet.
  """
  def media_url(%__MODULE__{media_dir: nil}), do: nil
  def media_url(%__MODULE__{status: status}) when status != "ready", do: nil

  def media_url(%__MODULE__{kind: "video", media_dir: dir}),
    do: Web.Uploads.entry_web_path(dir, Web.Media.master_playlist())

  def media_url(%__MODULE__{media_dir: dir}),
    do: Web.Uploads.entry_web_path(dir, Web.Media.audio_rendition())

  @doc "The entry's poster image, or `nil` if it has none yet."
  def poster_url(%__MODULE__{poster_path: path}) when is_binary(path), do: path
  def poster_url(%__MODULE__{}), do: nil

  @doc "True once the entry has media a visitor can actually play."
  def ready?(%__MODULE__{status: "ready"}), do: true
  def ready?(%__MODULE__{}), do: false

  def video?(%__MODULE__{kind: "video"}), do: true
  def video?(%__MODULE__{}), do: false

  @doc """
  The log's keywords as a normalized list, ready to render as chips or match
  a filter against.
  """
  @spec keyword_list(t :: %__MODULE__{}) :: [String.t()]
  def keyword_list(%__MODULE__{keywords: keywords}), do: Keywords.parse(keywords)

  defp normalize_keywords(changeset) do
    case fetch_change(changeset, :keywords) do
      {:ok, raw} -> put_change(changeset, :keywords, raw |> Keywords.parse() |> Keywords.format())
      :error -> changeset
    end
  end

  # The address is the date, so it is derived rather than entered — and
  # rederived whenever the date or the ordinal moves, since unlike a title
  # there is no editorial reason for the two to ever disagree.
  defp put_slug(changeset) do
    case {get_field(changeset, :recorded_on), get_field(changeset, :seq)} do
      {%Date{} = date, seq} when is_integer(seq) ->
        put_change(changeset, :slug, slug_for(date, seq))

      _ ->
        changeset
    end
  end
end
