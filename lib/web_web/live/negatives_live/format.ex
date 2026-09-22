defmodule WebWeb.NegativesLive.Format do
  @moduledoc """
  Path building for the contact sheet archive.

  Every control on `/negatives` is a link, and each one has to preserve what
  the others set — changing the sort must not lose which roll you were looking
  at, and stepping to the next roll must not drop the index you opened it from.
  So all of them compose their destination here rather than writing a path of
  their own.

  Defaults stay out of the query string, in the manner of
  `WebWeb.LogsLive.Format.logs_path/2` and `WebWeb.BlogHTML.blog_query/2`: the
  archive's resting state is a bare `/negatives/roll/013`, not that path
  trailing three parameters that only say "as usual".
  """

  use WebWeb, :verified_routes

  @doc """
  A roll's own address.

  `opts` carries the view state worth keeping across a step: `:mode` (`:index`
  to stay on the full table), `:sort`/`:dir` (the index's column order) and
  `:from` (which section the reader came in through, so the header's back
  control still knows after a reload).

  Roll tokens arrive in three spellings — `13`, `013`, `roll013` — and all of
  them resolve. This always emits the padded form, because that is what the
  page says out loud ("Roll #013") and one address per roll is worth having.
  """
  def sheet_path(roll, opts \\ []) do
    case query(opts) do
      [] -> ~p"/negatives/roll/#{pad(roll)}"
      params -> ~p"/negatives/roll/#{pad(roll)}?#{params}"
    end
  end

  @doc """
  The archive's front door, which opens on the most recent roll.

  Used by the index toggle and the sort headers, which are about the archive
  rather than any one roll.
  """
  def archive_path(opts \\ []) do
    case query(opts) do
      [] -> ~p"/negatives"
      params -> ~p"/negatives?#{params}"
    end
  end

  @doc "A single frame, under the roll it was cut from."
  def frame_path(roll, frame, opts \\ []) do
    case query(opts) do
      [] -> ~p"/negatives/roll/#{pad(roll)}/frame/#{frame}"
      params -> ~p"/negatives/roll/#{pad(roll)}/frame/#{frame}?#{params}"
    end
  end

  @doc """
  Zero-pads a roll token to three digits, the archive's own convention
  (`roll013_2026-08-03_120_bw`). Anything unrecognisable is passed through
  rather than mangled — the route's own parser decides what is valid.
  """
  def pad(roll) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})\z/i, to_string(roll)) do
      [_, digits] -> String.pad_leading(digits, 3, "0")
      _ -> to_string(roll)
    end
  end

  # Only what differs from the resting state survives into the URL.
  defp query(opts) do
    [
      {"mode", if(opts[:mode] == :index, do: "index")},
      {"sort", if(opts[:sort] == :format, do: "format")},
      {"dir", if(opts[:dir] == :asc, do: "asc")},
      {"from", opts[:from]}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end
end
