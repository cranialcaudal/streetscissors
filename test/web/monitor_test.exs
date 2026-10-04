defmodule Web.MonitorTest do
  use Web.DataCase
  use Oban.Testing, repo: Web.Repo

  alias Web.Backup
  alias Web.Monitor
  alias Web.Notify
  alias Web.Workers.OwnerMail

  @t0 ~U[2030-03-02 12:00:00Z]
  defp at(minutes), do: DateTime.add(@t0, minutes, :minute)

  # The monitor watches the overview's own checks too, and two of them fail
  # on an empty tmp dir. Give it a healthy machine to start from.
  setup do
    File.mkdir_p!(Backup.backup_dir())
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    snapshot = Path.join(Backup.backup_dir(), "web-#{stamp}.db")
    File.write!(snapshot, "")
    {:ok, _} = Backup.Content.run()

    Notify.put_address("author@example.com")

    on_exit(fn ->
      File.rm(snapshot)
      File.rm_rf!(Backup.Content.backup_dir())
    end)

    :ok
  end

  defp break_content_backup, do: File.rm_rf!(Backup.Content.backup_dir())
  defp mend_content_backup, do: {:ok, _} = Backup.Content.run()

  defp mail, do: all_enqueued(worker: OwnerMail)

  test "a healthy machine is recorded and nobody is written to" do
    assert Monitor.last() == %{at: nil, checks: []}

    Monitor.run(@t0)

    assert %{at: @t0, checks: []} = Monitor.last()
    assert mail() == []
  end

  # One dropped packet at the wrong moment is not an alarm.
  test "a failure is mailed on its second pass running, not its first" do
    break_content_backup()

    Monitor.run(at(0))
    assert mail() == []

    Monitor.run(at(15))

    assert [%{args: %{"to" => "author@example.com", "subject" => subject, "body" => body}}] =
             mail()

    assert subject == "streetscissors: written content needs you"
    assert body =~ "FAILING — Written content: no version on disk"
    assert body =~ "/admin/dashboard"
  end

  test "it is not repeated every pass, but is again after a day" do
    break_content_backup()
    Monitor.run(at(0))
    Monitor.run(at(15))
    Monitor.run(at(30))
    Monitor.run(at(60 * 12))
    assert [_one] = mail()

    Monitor.run(at(60 * 24 + 15))
    assert [reminder, _first] = Enum.sort_by(mail(), & &1.id, :desc)
    assert reminder.args["body"] =~ "STILL FAILING — Written content"
  end

  test "it is mentioned once more when it clears" do
    break_content_backup()
    Monitor.run(at(0))
    Monitor.run(at(15))

    mend_content_backup()
    Monitor.run(at(30))

    assert [cleared, _first] = Enum.sort_by(mail(), & &1.id, :desc)
    assert cleared.args["subject"] == "streetscissors: written content is working again"
    assert cleared.args["body"] =~ "CLEARED — Written content: 1 version kept"

    # And then it is forgotten: nothing more on the next pass.
    Monitor.run(at(45))
    assert length(mail()) == 2
  end

  test "a failure that cleared before anyone was told is dropped without a word" do
    break_content_backup()
    Monitor.run(at(0))

    mend_content_backup()
    Monitor.run(at(15))
    Monitor.run(at(30))

    assert mail() == []
  end

  test "with no address it still checks and records, and sends nothing" do
    Notify.put_address("")
    break_content_backup()

    Monitor.run(at(0))
    Monitor.run(at(15))

    assert mail() == []
    assert %{at: at} = Monitor.last()
    assert at == at(15)
  end

  test "run_scheduled/0 never raises" do
    assert :ok = Monitor.run_scheduled()
  end
end
