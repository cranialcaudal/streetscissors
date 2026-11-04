defmodule Web.Analytics.OwnerCountsTest do
  use Web.DataCase, async: false

  alias Web.Analytics
  alias Web.Analytics.{Owner, PageViewer}

  @mine "203.0.113.200"
  @reader "198.51.100.30"

  setup do
    # :persistent_term is outside the sandbox, so it is erased first and on its
    # own: the site_settings row is rolled back anyway, and a cleanup that
    # raised on the way to this line would leave the next test's visitor marked
    # as the author. That is how speed_test.exs — whose visitor is one of the
    # addresses below — started failing about one run in three.
    on_exit(fn -> :persistent_term.erase({Owner, :hashes}) end)

    Owner.reload()
    Owner.add(Analytics.hash_ip(@mine), source: "manual")
    :ok
  end

  defp mine, do: Analytics.hash_ip(@mine)
  defp reader, do: Analytics.hash_ip(@reader)

  # The decision was to keep the rows and leave them out of the figures, so
  # that a hash marked by mistake can be unmarked and nothing is lost.
  test "his visits stay in the table" do
    Analytics.record_hit("/blog/a-post", "Firefox", mine())

    assert Repo.aggregate(Analytics.Hit, :count, :id) == 1
  end

  test "today's views and visitors leave him out" do
    Analytics.record_hit("/blog/a-post", "Firefox", mine())
    Analytics.record_hit("/blog/a-post", "Firefox", mine())
    Analytics.record_hit("/blog/a-post", "Safari", reader())

    assert Analytics.count_hits_today() == 1
    assert Analytics.count_unique_visitors_today() == 1
  end

  test "a post's readers leave him out" do
    Analytics.record_hit("/blog/a-post", "Firefox", mine())
    Analytics.record_hit("/blog/a-post", "Safari", reader())

    assert %{"a-post" => 1} = Analytics.all_hits_by_prefix("/blog/%")
    assert %{"a-post" => 1} = Analytics.post_readers()
  end

  test "the top pages and the page's visitors leave him out" do
    Analytics.record_hit("/fitness", "Firefox", mine())
    Analytics.record_hit("/fitness", "Safari", reader())

    assert [{"/fitness", 1}] = Analytics.top_pages()
    assert %{"/fitness" => visitors} = Analytics.visitors_by_page(["/fitness"])
    assert MapSet.to_list(visitors) == [reader()]
  end

  test "the recent readers list leaves him out" do
    Analytics.record_hit("/fitness", "Firefox", mine())
    Analytics.record_hit("/fitness", "Safari", reader())

    assert [%{badge: badge}] = Analytics.recent_readers()
    assert badge == String.slice(reader(), 0, 6)
  end

  test "the dashboard's trend leaves him out" do
    Analytics.record_hit("/fitness", "Firefox", mine())
    Analytics.record_hit("/fitness", "Safari", reader())

    {total, _bins} = Analytics.get_biweekly_trends(2)

    assert total == 1
  end

  test "unmarking a hash puts his visits back in the figures" do
    Analytics.record_hit("/fitness", "Firefox", mine())

    assert Analytics.count_hits_today() == 0

    Owner.remove(mine())

    assert Analytics.count_hits_today() == 1
  end

  # A viewer row is kept for all time and nothing revisits it, so the author
  # becoming one is the single mistake in this area that cannot be undone.
  test "retention never folds him into a post's viewers" do
    Analytics.record_hit("/blog/a-post", "Firefox", mine())
    Analytics.record_hit("/blog/a-post", "Safari", reader())

    future = NaiveDateTime.add(NaiveDateTime.utc_now(), 401 * 86_400, :second)

    assert {:ok, %{deleted: 2}} = Analytics.prune(future)

    kept = Repo.all(PageViewer) |> Enum.map(& &1.ip_hash)

    assert kept == [reader()]
  end
end
