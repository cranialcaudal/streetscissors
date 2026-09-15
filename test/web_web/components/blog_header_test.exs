defmodule WebWeb.BlogHeaderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias WebWeb.CoreComponents

  test "the back control names only where it goes, and says it in full to screen readers" do
    html =
      render_component(&CoreComponents.blog_header/1,
        return_to: "/logs",
        return_label: "return to captain's logs"
      )

    assert html =~ ~s(href="/logs")
    assert html =~ ~s(aria-label="Back to captain&#39;s logs")
    assert html =~ ~s(<span class="header-action-label">captain&#39;s logs</span>)
    refute html =~ "return to"
  end

  test "both controls share one treatment" do
    html = render_component(&CoreComponents.blog_header/1, %{})

    assert html =~ "header-action header-action--back"
    assert html =~ "header-action header-action--contact"
    assert html =~ "Newsletter &amp; Contact"
    assert html =~ ~s(aria-label="Back to homepage")
    assert html =~ ~s(aria-label="streetscissors")
  end
end
