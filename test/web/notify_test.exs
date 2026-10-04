defmodule Web.NotifyTest do
  use Web.DataCase
  use Oban.Testing, repo: Web.Repo

  import Swoosh.TestAssertions

  alias Web.General
  alias Web.Notify
  alias Web.Workers.OwnerMail

  describe "address/0" do
    setup do
      on_exit(fn -> Application.delete_env(:web, :notify_email) end)
    end

    test "is nobody's until something says so" do
      assert Notify.address() == nil
      assert Notify.deliver("subject", "body") == :no_address
      assert all_enqueued(worker: OwnerMail) == []
    end

    test "the setting wins over the environment, and clearing it falls back" do
      Application.put_env(:web, :notify_email, "env@example.com")
      assert Notify.address() == "env@example.com"

      Notify.put_address("  admin@example.com ")
      assert Notify.address() == "admin@example.com"

      Notify.put_address("")
      assert Notify.address() == "env@example.com"
    end
  end

  describe "a guestbook signature" do
    test "is mailed to the author, with the words and the way to approve it" do
      Notify.put_address("author@example.com")

      {:ok, entry} = General.create_guestbook_entry(%{name: "Ada", message: "I read this twice."})

      assert [%{args: args}] = all_enqueued(worker: OwnerMail)
      assert args["to"] == "author@example.com"
      assert args["subject"] == "streetscissors: a signature is waiting"
      assert args["body"] =~ "Ada signed the guestbook"
      assert args["body"] =~ "I read this twice."
      assert args["body"] =~ "/admin/guestbook?show=held"
      refute entry.approved
    end

    test "is still held, and nothing is sent, when there is no address" do
      assert {:ok, entry} = General.create_guestbook_entry(%{name: "Ada", message: "Hello."})
      refute entry.approved
      assert all_enqueued(worker: OwnerMail) == []
    end
  end

  test "the worker delivers a plain letter with nothing in it to unsubscribe from" do
    assert {:ok, _} =
             perform_job(OwnerMail, %{
               "to" => "author@example.com",
               "subject" => "streetscissors: a test",
               "body" => "First paragraph.\n\nSecond <b>paragraph</b>."
             })

    assert_email_sent(fn email ->
      assert email.to == [{"", "author@example.com"}]
      assert email.subject == "streetscissors: a test"
      assert email.text_body == "First paragraph.\n\nSecond <b>paragraph</b>."
      # The body is the author's or a stranger's words: escaped, never markup.
      assert email.html_body =~ "Second &lt;b&gt;paragraph&lt;/b&gt;."
      refute email.html_body =~ "Unsubscribe"
      assert email.headers == %{}
    end)
  end
end
