defmodule Web.General.Contact do
  @moduledoc """
  The email address or phone number someone may leave when they sign the
  guestbook: for the author's eyes, and kept so that nobody else gets it.

  **It is never stored in the clear.** `seal/1` encrypts it (AES-256-GCM, by
  `Plug.Crypto`) under a key derived from the endpoint's `secret_key_base`,
  and `guestbook_entries.contact_sealed` holds only that. The secret lives in
  the environment (`.env`), which is in no backup: the nightly snapshots, the
  copies taken before migrations and the mirror on the removable drive all
  hold ciphertext, and a copy of the database is not a copy of anyone's
  phone number.

  The consequence to know about: **rotating `SECRET_KEY_BASE` makes every
  sealed contact unreadable**, for good. `open/1` answers `:error` for those,
  as it does for anything tampered with.

  Around it, the rest of the fence (each is tested in
  `test/web/guestbook_contact_test.exs`):

    * the column is `load_in_query: false`, so no query brings it back unless
      it names it. Only `Web.General.guestbook_contact/1` does, for the admin
    * the public page, the PubSub messages and the notification letter never
      carry it, sealed or open
    * `contact` is in `:filter_parameters`, so the form's value is
      `[FILTERED]` wherever parameters are logged, and both fields are
      `redact: true`, so an inspected struct or changeset shows `**redacted**`
  """

  @salt "guestbook contact"
  @max 120

  @doc "The longest a contact may be."
  def max_length, do: @max

  @doc "Encrypts a contact for storage."
  @spec seal(String.t()) :: String.t()
  def seal(contact) when is_binary(contact) do
    Plug.Crypto.encrypt(secret(), @salt, contact, max_age: :infinity)
  end

  @doc "Decrypts what `seal/1` made: `{:ok, contact}`, or `:error`."
  @spec open(term()) :: {:ok, String.t()} | :error
  def open(sealed) when is_binary(sealed) do
    case Plug.Crypto.decrypt(secret(), @salt, sealed, max_age: :infinity) do
      {:ok, contact} when is_binary(contact) -> {:ok, contact}
      _ -> :error
    end
  end

  def open(_sealed), do: :error

  @doc """
  Whether a string reads as an email address or a phone number. Deliberately
  loose: it is there to catch a message typed into the wrong box, not to
  judge addresses.
  """
  def plausible?(contact) when is_binary(contact) do
    email?(contact) or phone?(contact)
  end

  @doc "`:email`, `:phone`, or `nil`: what kind of link the admin can make of it."
  def kind(contact) when is_binary(contact) do
    cond do
      email?(contact) -> :email
      phone?(contact) -> :phone
      true -> nil
    end
  end

  defp email?(contact), do: contact =~ ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  defp phone?(contact) do
    digits = contact |> String.replace(~r/\D/, "") |> String.length()
    contact =~ ~r/\A\+?[\d\s().\-]+(\s*(x|ext\.?)\s*\d+)?\z/i and digits in 7..15
  end

  defp secret do
    Application.get_env(:web, WebWeb.Endpoint)[:secret_key_base] ||
      raise "secret_key_base is unset; a guestbook contact cannot be sealed"
  end
end
