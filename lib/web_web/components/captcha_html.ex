defmodule WebWeb.CaptchaHTML do
  use Phoenix.Component

  def simple_text(assigns) do
    ~H"""
    <div style="font-family: var(--font-homoglyph); font-weight: bold; color: var(--accent-color); margin-bottom: 0.5rem; text-align: left;">
      {@text}
    </div>
    """
  end
end
