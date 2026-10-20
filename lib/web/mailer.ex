defmodule Web.Mailer do
  @moduledoc """
  Sends email. This is Swoosh's mailer: `Web.Email` builds a message, and
  `Web.Mailer.deliver/1` sends it through whichever service `config/runtime.exs`
  names (Resend on the live site). In development, sent mail is kept in memory
  and shown at `/dev/mailbox`; in tests nothing is sent at all.
  """

  use Swoosh.Mailer, otp_app: :web
end
