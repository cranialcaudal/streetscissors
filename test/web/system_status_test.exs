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

  test "written content is a standing warning until it is backed up" do
    assert %{state: :warn} = SystemStatus.written_content()
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
