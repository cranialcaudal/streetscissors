defmodule Web.Backup.Content do
  @moduledoc """
  Versions of the written content.

  `Web.Backup` snapshots the database and `Web.Backup.Photos` mirrors the
  negatives, which left the writing itself with no copy anywhere. The vault is
  gitignored — the public repository is the site's code only — so the posts,
  the regimen and its wiki, the letter templates and the private notes existed
  once, on one disk. Of everything here they are the least replaceable: a ride
  re-syncs from Komoot and a negative can be scanned again, but an essay that
  is lost is lost.

  **What is kept.** The vault (`content/`) and the few files that live beside
  the code for the same reason it does: `scripts/`, the `/pc` terminal's two
  reading files, the recipe seed and `test/private/`. Whichever of them exist
  are archived; a fresh clone that has none is `{:error, :nothing_to_back_up}`.
  `.env` is deliberately not among them. The mirror is an unencrypted removable
  drive, and a credential can be reissued where a paragraph cannot.

  **A version is kept only when something changed.** Each run fingerprints
  every file by path and SHA-256. When that matches the newest archive the run
  is recorded and nothing is written, so `:content_backup_keep` counts
  *versions* rather than nights. Thirty nightly copies of a vault nobody
  touched reach back a month and hold one version; thirty versions reach back
  to the thirtieth edit, however long ago that was — which is what makes a
  paragraph deleted in August recoverable in October.

  Obsidian's `workspace.json` is left out for that reason. It records which
  panes are open and is rewritten every time a note is, so including it would
  make every run a new version of nothing.

  **Every archive is proven by restoring it.** A tarball of the right size is
  not evidence of anything. `verify/2` unpacks the archive into a scratch
  folder beside it and compares each file's hash against the manifest it was
  built from: every file present, none extra, none altered. Restoring by hand
  is the same operation: `tar -xzf content-….tar.gz -C somewhere`.

  **A second copy goes off the disk**, by the rule `Web.Backup` set: copied to
  `:content_mirror_path` when the drive is there, skipped with a log line when
  it is not. `sync_mirror/0` is what the drive watcher calls on plug-in.

  **Missed runs are caught up at boot**, as the database's are
  (`run_on_boot/0`, through `Web.Backup.catch_up/0`).

  Configure with `:content_backup_path` (where archives land),
  `:content_backup_keep`, `:content_mirror_path`, `:content_backup_root` (what
  the source paths are relative to, the checkout by default) and
  `:content_backup_sources`. The test env points all of them at fixtures and a
  tmp dir.
  """

  require Logger

  alias Web.Backup
  alias Web.Backup.Tree

  @default_keep 30
  @default_max_age_hours 20

  @default_sources [
    "content",
    "scripts",
    "priv/SEVEN_DAY_FITNESS.TXT",
    "priv/LINUX_POCKET_GUIDE.TXT",
    "priv/repo/seeds_recipes.exs",
    "test/private"
  ]

  # Rewritten by the editor rather than by the author.
  @volatile ~w(workspace.json workspace-mobile.json .DS_Store)

  @archive ~r/^content-(\d{8}-\d{6})-([0-9a-f]{12})\.tar\.gz$/
  @marker "last-run"

  @type version :: %{path: String.t(), size: non_neg_integer(), fingerprint: String.t()}

  @doc """
  Archives the content if it changed since the newest version.

  Returns `{:ok, path}` for a new version, `{:unchanged, path}` when the newest
  one already holds exactly what is on disk, or `{:error, reason}`.
  """
  @spec run() :: {:ok, String.t()} | {:unchanged, String.t()} | {:error, term()}
  def run do
    dir = backup_dir()
    File.mkdir_p!(dir)

    manifest = manifest()
    fingerprint = fingerprint(manifest)

    result =
      case {manifest, list()} do
        {[], _} ->
          {:error, :nothing_to_back_up}

        {_, [%{fingerprint: ^fingerprint, path: path} | _]} ->
          {:unchanged, path}

        _ ->
          write(dir, manifest, fingerprint)
      end

    case result do
      {:error, reason} ->
        Logger.error("content backup failed: #{inspect(reason)}")

      {outcome, path} ->
        record_run(dir)
        mirrored = sync_mirror()
        Logger.info("content backup: #{describe(outcome, path, manifest)}#{describe(mirrored)}")
    end

    result
  end

  @doc """
  Entry point for the scheduler. Never raises — a failed backup must not take
  the Quantum job (or anything sharing its supervisor) down with it.
  """
  def run_scheduled do
    run()
    :ok
  rescue
    error ->
      Logger.error("content backup crashed: #{Exception.message(error)}")
      :ok
  end

  @doc """
  Entry point for application start: runs when the last run is older than
  `:content_backup_max_age_hours`, so a night the machine spent asleep is made
  up for. Always returns `:ok`.
  """
  def run_on_boot do
    if Application.get_env(:web, :backup_on_boot, true) and stale?() do
      Logger.info("content backup: the last run is stale or missing, running at boot")
      run()
    end

    :ok
  rescue
    error ->
      Logger.error("content backup on boot crashed: #{Exception.message(error)}")
      :ok
  end

  # --- The manifest ----------------------------------------------------------

  @doc """
  Every file that would be archived, as `{name, path, sha256}` sorted by name.
  `name` is the path inside the archive, relative to the backup root.
  """
  @spec manifest() :: [{String.t(), String.t(), String.t()}]
  def manifest do
    root = root()

    sources()
    |> Enum.flat_map(fn source ->
      full = Path.expand(source, root)

      cond do
        File.dir?(full) -> Tree.walk(full)
        File.regular?(full) -> [full]
        true -> []
      end
    end)
    |> Enum.reject(&(Path.basename(&1) in @volatile))
    # A symlink is somebody else's file; only what is really here is ours to keep.
    |> Enum.filter(&match?({:ok, %{type: :regular}}, File.lstat(&1)))
    |> Enum.map(fn path -> {Path.relative_to(path, root), path, sha256(path)} end)
    |> Enum.sort()
  end

  @doc "Twelve hex digits standing for the whole manifest: every name and every hash."
  @spec fingerprint([{String.t(), String.t(), String.t()}]) :: String.t()
  def fingerprint(manifest) do
    manifest
    |> Enum.map(fn {name, _path, hash} -> [name, 0, hash, 0] end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp sha256(path) do
    path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  # --- Writing and proving ---------------------------------------------------

  defp write(dir, manifest, fingerprint) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    path = Path.join(dir, "content-#{stamp}-#{fingerprint}.tar.gz")

    entries =
      for {name, source, _hash} <- manifest,
          do: {String.to_charlist(name), String.to_charlist(source)}

    with :ok <- :erl_tar.create(String.to_charlist(path), entries, [:compressed]),
         :ok <- verify(path, manifest) do
      prune()
      {:ok, path}
    else
      {:error, reason} ->
        # An archive that cannot be restored is worse than none: it looks like
        # protection. Delete it so `list/0` never offers it.
        File.rm(path)
        {:error, reason}
    end
  end

  @doc """
  Unpacks an archive into a scratch folder beside it and checks it against a
  manifest: every file present, none extra, each with the hash it had on disk.
  """
  @spec verify(String.t(), [{String.t(), String.t(), String.t()}]) :: :ok | {:error, term()}
  def verify(path, manifest) do
    scratch = Path.join(Path.dirname(path), ".verify-#{System.unique_integer([:positive])}")
    File.mkdir_p!(scratch)

    try do
      with :ok <- extract(path, scratch) do
        expected = Map.new(manifest, fn {name, _path, hash} -> {name, hash} end)

        restored =
          Map.new(Tree.walk(scratch), fn file ->
            {Path.relative_to(file, scratch), sha256(file)}
          end)

        cond do
          restored == expected -> :ok
          map_size(restored) != map_size(expected) -> {:error, {:file_count, map_size(restored)}}
          true -> {:error, :contents_differ}
        end
      end
    after
      File.rm_rf(scratch)
    end
  end

  @doc """
  Unpacks an archive into a scratch folder beside it and checks it against
  the fingerprint in its own name: the archive still holds exactly the files,
  with exactly the bytes, that it was written with. This is what a restore
  rehearsal runs (`Web.Backup.Drill`), long after the files it was made from
  have moved on.

  Returns `{:ok, file_count}` or `{:error, reason}`.
  """
  @spec restore_check(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def restore_check(path) do
    scratch = Path.join(Path.dirname(path), ".drill-#{System.unique_integer([:positive])}")
    File.mkdir_p!(scratch)

    try do
      with [_, _stamp, written] <- Regex.run(@archive, Path.basename(path)),
           :ok <- extract(path, scratch) do
        restored =
          scratch
          |> Tree.walk()
          |> Enum.map(&{Path.relative_to(&1, scratch), &1, sha256(&1)})
          |> Enum.sort()

        if fingerprint(restored) == written,
          do: {:ok, length(restored)},
          else: {:error, "what unpacked is not what was archived"}
      else
        nil -> {:error, "not a content archive"}
        {:error, reason} -> {:error, reason}
      end
    after
      File.rm_rf(scratch)
    end
  end

  defp extract(path, into) do
    case :erl_tar.extract(String.to_charlist(path), [
           :compressed,
           {:cwd, String.to_charlist(into)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:unreadable, reason}}
    end
  end

  # --- The mirror ------------------------------------------------------------

  @doc "The configured off-disk destination, or `nil`. Empty string counts as unset."
  @spec mirror_dir() :: String.t() | nil
  def mirror_dir do
    case Application.get_env(:web, :content_mirror_path) do
      nil -> nil
      "" -> nil
      dir -> dir
    end
  end

  @doc "True when a mirror is configured and its drive is there."
  @spec mirror_available?() :: boolean()
  def mirror_available?, do: Backup.mirror_reachable?(mirror_dir())

  @doc """
  Copies across every version the mirror does not have, then applies retention
  there too.

  Returns `{:ok, %{copied: n, failed: n, present: n}}`, or `:unavailable` when
  no mirror is configured or the drive is not there. Never raises.
  """
  @spec sync_mirror() :: {:ok, map()} | :unavailable
  def sync_mirror do
    case Backup.claim_mirror(mirror_dir()) do
      :absent ->
        :unavailable

      {:ok, dir} ->
        have = MapSet.new(list_dir(dir), &Path.basename(&1.path))

        results =
          list()
          |> Enum.reject(&MapSet.member?(have, Path.basename(&1.path)))
          # Newest first from list/0; copy oldest first so an interrupted sync
          # still leaves the mirror's newest file being the newest one it has.
          |> Enum.reverse()
          |> Enum.map(&copy_to_mirror(&1.path, dir))

        prune_dir(dir)

        {:ok,
         %{
           copied: Enum.count(results, &(&1 == :ok)),
           failed: Enum.count(results, &(&1 != :ok)),
           present: length(list_dir(dir))
         }}
    end
  rescue
    error ->
      Logger.error("content backup: mirror sync crashed: #{Exception.message(error)}")
      {:ok, %{copied: 0, failed: 1, present: 0}}
  end

  # The copy counts only if it reads back byte for byte: a drive pulled
  # mid-write leaves a file of plausible size and no use.
  defp copy_to_mirror(path, dir) do
    dest = Path.join(dir, Path.basename(path))

    with :ok <- File.cp(path, dest),
         true <- sha256(dest) == sha256(path) do
      :ok
    else
      _ ->
        File.rm(dest)
        :error
    end
  end

  # --- What is on disk -------------------------------------------------------

  @doc "Versions on disk, newest first."
  @spec list() :: [version()]
  def list, do: list_dir(backup_dir())

  @doc "Versions in an arbitrary directory, newest first. Used for the mirror."
  @spec list_dir(String.t()) :: [version()]
  def list_dir(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn name ->
          case Regex.run(@archive, name) do
            [_, _stamp, fingerprint] ->
              full = Path.join(dir, name)
              [%{path: full, size: File.stat!(full).size, fingerprint: fingerprint}]

            nil ->
              []
          end
        end)
        # Names lead with a zero-padded timestamp, so sorting by name is
        # chronological and does not depend on mtimes surviving a copy.
        |> Enum.sort_by(& &1.path, :desc)

      _ ->
        []
    end
  end

  @doc "Deletes all but the newest `:content_backup_keep` versions. Returns how many went."
  @spec prune() :: non_neg_integer()
  def prune, do: prune_dir(backup_dir())

  @doc "Applies the retention policy to an arbitrary directory."
  @spec prune_dir(String.t()) :: non_neg_integer()
  def prune_dir(dir) do
    dir
    |> list_dir()
    |> Enum.drop(keep())
    |> Enum.map(fn %{path: path} -> File.rm(path) end)
    |> Enum.count(&(&1 == :ok))
  end

  # --- When it last ran ------------------------------------------------------

  @doc """
  When the content was last checked, changed or not, or `nil` if never.

  A run that finds nothing new writes no archive, so the newest archive's date
  says when the content last *changed*. This is the other question: is the
  schedule still alive.
  """
  @spec last_run() :: DateTime.t() | nil
  def last_run do
    with {:ok, text} <- File.read(Path.join(backup_dir(), @marker)),
         {:ok, at, _offset} <- DateTime.from_iso8601(String.trim(text)) do
      at
    else
      _ -> nil
    end
  end

  @doc "True when the content has never been checked, or not within `:content_backup_max_age_hours`."
  @spec stale?() :: boolean()
  def stale? do
    case last_run() do
      nil -> true
      at -> DateTime.diff(DateTime.utc_now(), at, :second) / 3600 > max_age_hours()
    end
  end

  defp record_run(dir) do
    File.write!(Path.join(dir, @marker), DateTime.to_iso8601(DateTime.utc_now()))
  end

  # --- Configuration ---------------------------------------------------------

  def backup_dir do
    Application.get_env(:web, :content_backup_path) ||
      Path.join(System.user_home!(), "streetscissors-backups/content")
  end

  defp root, do: Application.get_env(:web, :content_backup_root) || File.cwd!()
  defp sources, do: Application.get_env(:web, :content_backup_sources, @default_sources)
  defp keep, do: Application.get_env(:web, :content_backup_keep, @default_keep)

  defp max_age_hours,
    do: Application.get_env(:web, :content_backup_max_age_hours, @default_max_age_hours)

  # --- Log lines -------------------------------------------------------------

  defp describe(:ok, path, manifest), do: "wrote #{path} (#{length(manifest)} files)"
  defp describe(:unchanged, path, _manifest), do: "nothing changed since #{Path.basename(path)}"

  defp describe(:unavailable), do: ", mirror unavailable"
  defp describe({:ok, %{failed: failed}}) when failed > 0, do: ", MIRROR FAILED for #{failed}"
  defp describe({:ok, %{copied: 0}}), do: ", mirror up to date"
  defp describe({:ok, %{copied: copied}}), do: ", mirrored #{copied}"
end
