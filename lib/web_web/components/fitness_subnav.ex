defmodule WebWeb.FitnessSubnav do
  @moduledoc """
  The fitness section's tab row (Regimen / Wiki / Activities / Biometrics),
  shared by every fitness LiveView. The current page's own tab is omitted,
  matching the section's original navigation convention.

  The Kitchen is **not** in this list. It moved to an unlisted /food and is the
  one fitness page nothing is allowed to link to — putting it back here is all
  it would take to make it public again.
  """
  use Phoenix.Component

  @tabs [
    {:regimen, "/fitness", "Regimen"},
    {:wiki, "/fitness/wiki", "Wiki"},
    {:rides, "/fitness/rides", "Activities"}
  ]

  attr :active, :atom, required: true
  attr :is_admin, :boolean, default: false

  def subnav(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <div
      class="bento-fitness-sub-row"
      style="display: flex; flex-wrap: wrap; gap: 1rem; margin-bottom: 2rem;"
    >
      <%= for {key, href, label} <- @tabs, key != @active do %>
        <a
          href={href}
          class="bento-card bento-card-skinny"
          style="flex: 1; min-width: 130px; text-align: center; padding: 1rem; background: rgba(23, 20, 15, 0.05); border: 1px solid rgba(23, 20, 15, 0.1); border-radius: 12px; text-decoration: none;"
        >
          <span
            class="bento-label-small"
            style="color: var(--ink); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px;"
          >
            {label}
          </span>
        </a>
      <% end %>
      <%= if @is_admin and @active != :biometrics do %>
        <a
          href="/fitness/biometrics"
          class="bento-card bento-card-skinny"
          style="flex: 1; min-width: 130px; text-align: center; padding: 1rem; background: rgba(23, 20, 15, 0.05); border: 1px solid rgba(23, 20, 15, 0.1); border-radius: 12px; text-decoration: none;"
        >
          <span
            class="bento-label-small"
            style="color: var(--ink); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px;"
          >
            Biometrics
          </span>
        </a>
      <% end %>
    </div>
    """
  end
end
