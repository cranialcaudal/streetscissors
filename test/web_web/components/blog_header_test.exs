defmodule WebWeb.BlogHeaderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias WebWeb.CoreComponents

  test "the back control names only where it goes, and says it in full to screen readers" do
    html =
      render_component(&CoreComponents.blog_header/1,
        return_to: "/logs",
        return_label: "return to videostream"
      )

    assert html =~ ~s(href="/logs")
    assert html =~ ~s(aria-label="Back to Videostream")
    assert html =~ ~s(<span class="header-action-label">Videostream</span>)
    refute html =~ "return to"
  end

  test "both controls share one treatment" do
    html = render_component(&CoreComponents.blog_header/1, %{})

    assert html =~ "header-action header-action--back"
    assert html =~ "header-action header-action--contact"
    assert html =~ "Newsletter &amp; Contact"
    assert html =~ ~s(aria-label="Back to Home")
    assert html =~ ~s(<span class="header-action-label">Home</span>)
    assert html =~ ~s(aria-label="streetscissors")
  end

  test "site_sections standardizes Videostream and highlights active section" do
    html = render_component(&CoreComponents.site_sections/1, active: :logs)
    assert html =~ "Videostream"
    assert html =~ ~s(href="/logs" class="site-section-link is-active" aria-current="page")
  end
end
