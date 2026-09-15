defmodule Web.AnalyticsTest do
  use Web.DataCase

  alias Web.Analytics

  # Hits store `conn.request_path`, which is percent-encoded. Post slugs are
  # not. Both of these bugs were live: every post read "0 views" because the
  # encoded path never matched its slug, and the number being counted was page
  # loads rather than people.
  describe "all_hits_by_prefix/1" do
    test "decodes the percent-encoded path so it matches the post slug" do
      Analytics.record_hit("/blog/Tide%27s%20Out%2C%20Mostly", "Firefox", "visitor-a")

      assert %{"Tide's Out, Mostly" => 1} = Analytics.all_hits_by_prefix("/blog/%")
    end

    test "collapses the encodings clients actually send onto one slug" do
      # Same post, three ways: fully encoded, apostrophe left literal, and
      # comma left literal. All three appear in the production table.
      Analytics.record_hit("/blog/Salt%27s%20in%20the%20Air", "Firefox", "visitor-a")
      Analytics.record_hit("/blog/Salt's%20in%20the%20Air", "Safari", "visitor-b")
      Analytics.record_hit("/blog/Salt%27s in the Air", "Chrome", "visitor-c")

      assert %{"Salt's in the Air" => 3} = Analytics.all_hits_by_prefix("/blog/%")
    end

    test "counts visitors, not page loads" do
      for _ <- 1..10 do
        Analytics.record_hit("/blog/post", "Firefox", "the-same-visitor")
      end

      assert %{"post" => 1} = Analytics.all_hits_by_prefix("/blog/%")
    end

    test "counts a visitor once even across differently encoded paths" do
      Analytics.record_hit("/blog/Salt%27s%20in%20the%20Air", "Firefox", "visitor-a")
      Analytics.record_hit("/blog/Salt's%20in%20the%20Air", "Firefox", "visitor-a")

      assert %{"Salt's in the Air" => 1} = Analytics.all_hits_by_prefix("/blog/%")
    end

    test "keeps separate posts separate" do
      Analytics.record_hit("/blog/one", "Firefox", "visitor-a")
      Analytics.record_hit("/blog/two", "Firefox", "visitor-a")
      Analytics.record_hit("/blog/two", "Firefox", "visitor-b")

      counts = Analytics.all_hits_by_prefix("/blog/%")

      assert counts["one"] == 1
      assert counts["two"] == 2
    end

    test "respects the prefix" do
      Analytics.record_hit("/blog/post", "Firefox", "visitor-a")
      Analytics.record_hit("/logs/episode", "Firefox", "visitor-a")

      counts = Analytics.all_hits_by_prefix("/blog/%")

      assert Map.has_key?(counts, "post")
      refute Map.has_key?(counts, "episode")
    end
  end

  describe "hash_ip/1" do
    test "is stable, so a returning visitor stays one visitor" do
      assert Analytics.hash_ip("203.0.113.7") == Analytics.hash_ip("203.0.113.7")
    end

    test "separates different addresses" do
      refute Analytics.hash_ip("203.0.113.7") == Analytics.hash_ip("203.0.113.8")
    end

    # The whole point of the salt: an unsalted SHA-256 of an IPv4 address is
    # reversible by hashing all four billion of them.
    test "is salted, not a bare digest of the address" do
      bare = :crypto.hash(:sha256, "203.0.113.7") |> Base.encode16()

      refute Analytics.hash_ip("203.0.113.7") == bare
    end
  end

  describe "bot_user_agent?/1" do
    test "catches named crawlers" do
      assert Analytics.bot_user_agent?("serpstatbot/2.1 (advanced backlink tracking bot)")
      assert Analytics.bot_user_agent?("Mozilla/5.0 (compatible; SeznamBot/4.0)")
      assert Analytics.bot_user_agent?("Scrapy/2.16.0 (+https://scrapy.org)")
      assert Analytics.bot_user_agent?("python-requests/2.32.4")
    end

    # Well-behaved bots advertise a contact URL; browsers never do. This is
    # what catches the one-off scanners that have no recognisable name.
    test "catches self-identifying bots by their contact URL" do
      assert Analytics.bot_user_agent?(
               "Mozilla/5.0 (compatible; CMS-Checker/1.0; +https://x.com)"
             )

      assert Analytics.bot_user_agent?("Mozilla/5.0 (compatible; Whatever/0.1; +http://y.net)")
    end

    test "leaves real browsers alone" do
      refute Analytics.bot_user_agent?(
               "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 Mobile/15E148 Safari/604.1"
             )

      refute Analytics.bot_user_agent?(
               "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
             )

      refute Analytics.bot_user_agent?(
               "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:152.0) Gecko/20100101 Firefox/152.0"
             )
    end

    test "handles a missing user agent" do
      refute Analytics.bot_user_agent?(nil)
    end
  end

  describe "sub_resource_path?/1" do
    test "flags controller-served images, which are not page views" do
      assert Analytics.sub_resource_path?("/negatives/preview/roll012.jpg")
      assert Analytics.sub_resource_path?("/negatives/image/roll012.jpg")
      assert Analytics.sub_resource_path?("/fitness/rides/123/thumb")
    end

    test "leaves real pages alone" do
      refute Analytics.sub_resource_path?("/negatives")
      refute Analytics.sub_resource_path?("/blog/Tide%27s%20Out%2C%20Mostly")
      refute Analytics.sub_resource_path?("/fitness/rides")
    end
  end
end
