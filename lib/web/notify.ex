defmodule Web.Notify do
  @moduledoc """
  The site writing to its author.

  Two things here used to wait until someone happened to open the admin: a
  guestbook signature held for approval, and a fault on the machine. Both now
  arrive as mail, at one address.

  The address is the `notify_email` site setting (Settings → Alerts), with
  `:notify_email` (`NOTIFY_EMAIL`) as the fallback for a deploy that would
  rather keep it in the environment. It is nobody's until one of those says
  so: with neither set, nothing is sent and the overview says there is nowhere
  to write to.

  Delivery is an Oban job on the `mailers` queue, so a message written while
  the mail provider is unreachable is retried rather than lost — and a fault
  is exactly when the network is least to be trusted.
  """

  alias Web.General.GuestbookEntry
  alias Web.SiteSettings
  alias Web.Workers.OwnerMail

  @setting "notify_email"
  @excerpt 600

  @doc "Where the site writes to, or `nil` when no address is set."
  @spec address() :: String.t() | nil
  def address do
    present(SiteSettings.get_setting(@setting)) ||
      present(Application.get_env(:web, :notify_email))
  end

  @doc "Sets the address from the admin. An empty string clears it."
  def put_address(email) do
    case String.trim(email) do
      # A setting cannot hold an empty value, so clearing one is deleting it.
      "" -> SiteSettings.delete_setting(@setting)
      address -> SiteSettings.put_setting(@setting, address)
    end
  end

  @doc """
  Queues a plain message to the author.

  Returns `{:ok, job}`, or `:no_address` when there is nowhere to send it.
  """
  @spec deliver(String.t(), String.t()) :: {:ok, Oban.Job.t()} | :no_address | {:error, term()}
  def deliver(subject, body) do
    case address() do
      nil ->
        :no_address

      to ->
        %{"to" => to, "subject" => subject, "body" => body}
        |> OwnerMail.new()
        |> Oban.insert()
    end
  end

  @doc "Tells the author a signature is waiting, with the words themselves."
  def guestbook_signature(%GuestbookEntry{} = entry) do
    deliver(
      "streetscissors: a signature is waiting",
      """
      #{entry.name} signed the guestbook:

      #{excerpt(entry.message)}
      #{if entry.has_contact, do: "\nThey left a way to reach them. It is not in this letter; it is in the admin.\n", else: ""}
      It is held until you approve it:
      #{WebWeb.Endpoint.url()}/admin/guestbook?show=held
      """
    )
  end

  defp excerpt(nil), do: ""

  defp excerpt(text) do
    if String.length(text) > @excerpt, do: String.slice(text, 0, @excerpt) <> "…", else: text
  end

  defp present(nil), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
