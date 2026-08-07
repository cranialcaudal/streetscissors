defmodule WebWeb.Unsubscribe do
  @moduledoc """
  Unsubscribe links.

  The token is a random per-subscriber value stored on the row, not a signature
  over the address. Two reasons:

    * **It outlives key rotation.** `Phoenix.Token` is keyed on
      `secret_key_base`; rotating that would silently break every unsubscribe
      link in every message already sent. These links have to keep working out
      of a mail archive years later — an expired one is a compliance failure.
    * **It reveals nothing.** The address is not recoverable from the token, so
      the endpoint cannot be edited to unsubscribe somebody else or walked to
      discover who is on the list.

  A token that is not in the database is simply an invalid link.
  """

  alias Web.Newsletter

  @doc """
  The token for an address, or `nil` if it is not a subscriber.

  Callers building an email already know the recipient is on the list, so a
  `nil` here means something is wrong upstream rather than that the message
  should go out without a link.
  """
  @spec token(String.t()) :: String.t() | nil
  def token(email) do
    case Newsletter.get_subscriber(email) do
      %{unsubscribe_token: token} when is_binary(token) -> token
      _ -> nil
    end
  end

  @doc "Resolves a token to its subscriber, or `:error`."
  @spec verify(String.t()) :: {:ok, Web.Newsletter.Subscriber.t()} | :error
  def verify(token) when is_binary(token) and token != "" do
    case Newsletter.get_by_unsubscribe_token(token) do
      nil -> :error
      subscriber -> {:ok, subscriber}
    end
  end

  def verify(_), do: :error

  @doc "The human-facing page: explains, then asks for one click to confirm."
  @spec url(String.t()) :: String.t() | nil
  def url(email), do: build_url(token(email), "")

  @doc """
  The RFC 8058 one-click endpoint, which mail clients POST to directly.
  Referenced by the `List-Unsubscribe` header rather than shown to readers.
  """
  @spec one_click_url(String.t()) :: String.t() | nil
  def one_click_url(email), do: build_url(token(email), "/one-click")

  defp build_url(nil, _suffix), do: nil
  defp build_url(token, suffix), do: WebWeb.SEO.absolute("/unsubscribe/#{token}#{suffix}")
end
