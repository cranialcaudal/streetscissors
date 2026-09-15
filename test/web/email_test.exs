defmodule Web.EmailTest do
  # DataCase: the unsubscribe headers look the subscriber up. Not async: one
  # test points :emails_path at an empty directory.
  use Web.DataCase

  alias Web.Email

  # The letter comes from test/support/fixtures/emails (config/test.exs).

  describe "welcome/1" do
    test "sends the letter from the emails directory as HTML and as text" do
      email = Email.welcome("reader@example.com")

      assert email.subject == "Welcome to streetscissors"

      assert email.html_body =~ "Fixture welcome letter."
      assert email.html_body =~ "<li>"
      assert email.html_body =~ "Unsubscribe"

      assert email.text_body =~ "Fixture welcome letter."
      assert email.text_body =~ "- First point"
      assert email.text_body =~ "Unsubscribe:"
    end

    test "falls back to a short neutral note without a letter file" do
      tmp = Path.join(System.tmp_dir!(), "email_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      prev = Application.get_env(:web, :emails_path)
      Application.put_env(:web, :emails_path, tmp)

      try do
        email = Email.welcome("reader@example.com")

        assert email.html_body =~ "Thanks for subscribing"
        assert email.text_body =~ "Thanks for subscribing"
        refute email.text_body =~ "Fixture"
      after
        Application.put_env(:web, :emails_path, prev)
        File.rm_rf!(tmp)
      end
    end
  end
end
