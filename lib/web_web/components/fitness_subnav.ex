defmodule WebWeb.FitnessSubnav do
  @moduledoc """
  The fitness section's tab row (Week / Wiki / Activities),
  shared by every fitness LiveView. All three are always shown, in this order,
  with the page being looked at marked: while the current page's own tab was
  left out, each page showed a different pair and a first visitor could not
  tell what the section held.

  The Kitchen is **not** in this list. It moved to an unlisted /food and is the
  one fitness page nothing is allowed to link to — putting it back here is all
  it would take to make it public again.
  """
  use Phoenix.Component

  @tabs [
    {:regimen, "/fitness", "Week"},
    {:wiki, "/fitness/wiki", "Wiki"},
    {:rides, "/fitness/rides", "Activities"}
  ]

  attr :active, :atom, required: true

  def subnav(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <nav class="tabs" aria-label="Fitness">
      <a :for={{key, href, label} <- @tabs} href={href} aria-current={key == @active && "page"}>
        {label}
      </a>
    </nav>
    """
  end
end
