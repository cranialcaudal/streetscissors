defmodule Web.SystemStatusTest do
  use Web.DataCase

  alias Web.Backup
  alias Web.Rides.KomootSync
  alias Web.SystemStatus

  defp fresh_snapshot do
    File.mkdir_p!(Backup.backup_dir())
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    path = Path.join(Backup.backup_dir(), "web-#{stamp}.db")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)
    path
  end

  test "every check has a label, a state and something to say" do
    for check <- SystemStatus.checks() do
      assert check.state in [:ok, :warn, :fail, :off]
      assert is_binary(check.label) and is_binary(check.detail)
    end
  end

  test "a fresh snapshot is healthy, with its time" do
    fresh_snapshot()
    assert %{state: :ok, at: %DateTime{}} = SystemStatus.database_snapshots()
  end

  test "an unconfigured mirror is off, not a fault" do
    assert %{state: :off} = SystemStatus.backup_mirror()
  end

  describe "written content" do
    setup do
      dir = Backup.Content.backup_dir()
      File.rm_rf!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      :ok
    end

    test "fails until there is a version on disk" do
      assert %{state: :fail, detail: "no version on disk"} = SystemStatus.written_content()
    end

    test "is healthy after a run, and says when it last ran" do
      {:ok, _} = Backup.Content.run()

      assert %{state: :ok, detail: "1 version kept", at: %DateTime{}} =
               SystemStatus.written_content()
    end

    test "warns when the schedule has gone quiet" do
      {:ok, _} = Backup.Content.run()
      two_days_ago = DateTime.add(DateTime.utc_now(), -48, :hour)

      File.write!(
        Path.join(Backup.Content.backup_dir(), "last-run"),
        DateTime.to_iso8601(two_days_ago)
      )

      assert %{state: :warn} = SystemStatus.written_content()
    end
  end

  test "the content and recordings copies are off, not faults, when unconfigured" do
    assert %{state: :off} = SystemStatus.content_mirror()
    assert %{state: :off} = SystemStatus.recordings_mirror()
  end

  test "the Komoot check follows the last pass" do
    assert %{state: :off, detail: "no pass recorded yet"} = SystemStatus.komoot()

    KomootSync.record_run({:error, :auth_failed})
    assert %{state: :fail, detail: ":auth_failed"} = SystemStatus.komoot()

    KomootSync.record_run(
      {:ok, %{imported: 2, updated: 0, deleted: 0, failed: 0, unchanged: false}}
    )

    assert %{state: :ok, detail: "2 imported"} = SystemStatus.komoot()
  end

  test "failed newsletter jobs show in the mail queue" do
    assert %{state: :ok} = SystemStatus.mail_queue()

    %{"email" => "x@example.com", "subject" => "s", "body" => "b"}
    |> Web.Workers.NewsletterSender.new()
    |> Ecto.Changeset.put_change(:state, "discarded")
    |> Repo.insert!()

    assert %{state: :fail, detail: "1 send failed or retrying"} = SystemStatus.mail_queue()
  end
end
