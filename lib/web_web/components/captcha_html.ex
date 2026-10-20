defmodule WebWeb.CaptchaHTML do
  @moduledoc """
  Draws the captcha's challenge text on the contact and guestbook forms. The
  challenge itself (what it asks, and checking the answer) is `WebWeb.Captcha`.
  """

  use Phoenix.Component

  def simple_text(assigns) do
    ~H"""
    <div style="font-family: var(--font-homoglyph); font-weight: bold; color: var(--accent-color); margin-bottom: 0.5rem; text-align: left;">
      {@text}
    </div>
    """
  end
end
