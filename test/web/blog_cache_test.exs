defmodule Web.BlogCacheTest do
  # The blog's folder is application config: not async.
  use ExUnit.Case, async: false

  alias Web.Blog

  setup do
    dir = Path.join(System.tmp_dir!(), "blog_cache_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    previous = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, dir)

    on_exit(fn ->
      Application.put_env(:web, :blog_path, previous)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  defp post(title, extra \\ ""),
    do: "---\ntitle: #{title}\ndate: 2026-09-01\n#{extra}---\n\nWords.\n"

  test "a post saved again is read again, however it was saved", %{dir: dir} do
    path = Path.join(dir, "harbour.md")
    File.write!(path, post("Harbour"))
    assert [%{title: "Harbour"}] = Blog.list_posts()

    # Through the site: written beside and renamed over.
    {:ok, %{revision: revision}} = Blog.read_source("harbour")
    {:ok, _} = Blog.write_source("harbour", post("Harbour, again"), revision)
    assert [%{title: "Harbour, again"}] = Blog.list_posts()

    # By hand, in place, to a different length.
    File.write!(path, post("Harbour by hand", "description: changed\n"))
    assert [%{title: "Harbour by hand"}] = Blog.list_posts()
  end

  test "a draft stays hidden, cached or not", %{dir: dir} do
    File.write!(Path.join(dir, "secret.md"), post("Secret", "draft: true\n"))
    assert Blog.list_posts() == []
    assert Blog.list_posts() == []
    assert {:error, :not_found} = Blog.get_post("secret")
  end
end
