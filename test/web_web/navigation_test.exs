defmodule WebWeb.NavigationTest do
  use WebWeb.ConnCase

  alias WebWeb.Navigation

  describe "return_context/1" do
    # The blog's masthead is "Written Work"; its back link used to say the
    # site's name instead, which the logo beside it already says.
    test "every blog-family token returns to written work" do
      for from <- ~w[blog latent-sensus sensus another-blog reflections sports-blog] do
        assert Navigation.return_context(from) == {"/blog", "return to written work"}
      end
    end

    test "unknown or missing tokens fall back to the homepage" do
      assert Navigation.return_context(nil) == {"/", "return to homepage"}
      assert Navigation.return_context("nowhere") == {"/", "return to homepage"}
    end
  end

  test "a post's back control names written work", %{conn: conn} do
    html = conn |> get(~p"/blog/frontmatter-and-embeds") |> html_response(200)

    assert html =~ ~s(aria-label="Back to written work")
    refute html =~ "return to streetscissors"
  end
end
