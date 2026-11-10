defmodule WebWeb.OutsideHostsTest do
  @moduledoc """
  What a page makes a browser fetch from another site: nothing, the playlist on
  the home page aside.

  A stylesheet, script, font, picture or frame served by another host tells
  that host who is reading and which page. A link out is the reader's own
  choice and is not counted. This reads the templates and stylesheets as they
  are written, so an address a template is handed at run time (the admin's
  Komoot embed) is not seen here.
  """
  use ExUnit.Case, async: true

  # {tag, host}
  @allowed [{"iframe", "open.spotify.com"}]

  test "no template has a browser load anything from another host" do
    found =
      for file <- Path.wildcard("lib/web_web/**/*.{ex,heex}"),
          {tag, host} <- outside_loads(File.read!(file)),
          {tag, host} not in @allowed,
          do: "#{file}: <#{tag}> loads from #{host}"

    assert found == []
  end

  test "no stylesheet names another host" do
    found =
      for file <- Path.wildcard("assets/css/**/*.css"),
          File.read!(file) =~ ~r{(?:url\(\s*|@import\s+)["']?(?:https?:)?//},
          do: file

    assert found == []
  end

  test "the check sees a load, on one line or several, and passes a link by" do
    assert outside_loads(~s(<script src="https://cdn.example/x.js"></script>)) ==
             [{"script", "cdn.example"}]

    assert outside_loads("""
           <link
             href="//fonts.example/css2?family=A"
             rel="stylesheet"
           />
           <img :if={@n < 3} src={"https://img.example/\#{@id}.jpg"} />
           """) == [{"link", "fonts.example"}, {"img", "img.example"}]

    assert outside_loads("""
           <a href="https://elsewhere.example/page">out</a>
           <.link href={"https://elsewhere.example/\#{@id}"}>out</.link>
           <img src={~p"/images/here.png"} />
           """) == []
  end

  # Every {tag, host} where a tag other than a link names another host in an
  # attribute a browser fetches without being asked.
  defp outside_loads(source) do
    ~r{\s(?:src|href|srcset|poster|data)=\{?"(?:https?:)?//([^/"?#\s]+)}
    |> Regex.scan(source, return: :index)
    |> Enum.map(fn [{at, _}, {host_at, host_length}] ->
      {tag_before(source, at), binary_part(source, host_at, host_length)}
    end)
    |> Enum.reject(fn {tag, _host} -> tag in ["a", ".link"] end)
  end

  defp tag_before(source, at) do
    ~r{<([A-Za-z.][\w.:-]*)}
    |> Regex.scan(binary_part(source, 0, at), capture: :all_but_first)
    |> List.last([nil])
    |> hd()
  end
end
