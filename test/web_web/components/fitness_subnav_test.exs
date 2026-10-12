defmodule WebWeb.FitnessSubnavTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  for active <- [:regimen, :wiki, :rides] do
    test "all three tabs show when #{active} is the page, and it alone is marked" do
      html = render_component(&WebWeb.FitnessSubnav.subnav/1, active: unquote(active))
      for label <- ["Regimen", "Wiki", "Activities"], do: assert(html =~ label)
      assert length(String.split(html, ~s(aria-current="page"))) == 2
    end
  end
end
