defmodule WebWeb.LegacyRedirectControllerTest do
  use WebWeb.ConnCase

  test "manuscripts URLs permanently redirect to the blog" do
    for {old, new} <- [
          {"/manuscripts", "/blog"},
          {"/manuscripts/latent-sensus", "/blog"},
          {"/manuscripts/fitness-blog", "/blog"},
          {"/manuscripts/latent-sensus/some-old-post", "/blog/some-old-post"},
          # Audio was never really part of a post; spoken work is its own
          # section now, so every old audio path lands on /logs.
          {"/manuscripts/latent-sensus/audio/some-old-post.mp3", "/logs"},
          {"/manuscripts/anything/some-post", "/blog"},
          {"/manuscripts/anything/audio/x.mp3", "/logs"}
        ] do
      conn = get(build_conn(), old)
      assert redirected_to(conn, 301) == new, "#{old} should 301 to #{new}"
    end
  end

  test "old fitness-blog URLs permanently redirect to the fitness landing" do
    for old <- ["/fitness/regimen", "/fitness/some-old-post"] do
      conn = get(build_conn(), old)
      assert redirected_to(conn, 301) == "/fitness", "#{old} should 301 to /fitness"
    end
  end
end
