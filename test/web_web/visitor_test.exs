defmodule WebWeb.VisitorTest do
  use WebWeb.ConnCase, async: false

  alias WebWeb.Visitor

  describe "ip/1 for a conn" do
    test "behind the proxy, the first hop of x-forwarded-for", %{conn: conn} do
      conn = put_req_header(conn, "x-forwarded-for", "203.0.113.5, 10.0.0.1")
      assert Visitor.ip(conn) == "203.0.113.5"
    end

    test "IPv6 clients come through whole", %{conn: conn} do
      conn = put_req_header(conn, "x-forwarded-for", "2001:db8::7")
      assert Visitor.ip(conn) == "2001:db8::7"
    end

    test "with no header, the peer", %{conn: conn} do
      assert Visitor.ip(conn) == "127.0.0.1"
    end

    # Reached around the proxy, a caller could name any address it liked.
    test "a peer that is not the proxy cannot claim an address", %{conn: conn} do
      conn = %{conn | remote_ip: {198, 51, 100, 4}}
      conn = put_req_header(conn, "x-forwarded-for", "203.0.113.5")
      assert Visitor.ip(conn) == "198.51.100.4"
    end

    test "an empty header falls back to the peer", %{conn: conn} do
      conn = put_req_header(conn, "x-forwarded-for", " ")
      assert Visitor.ip(conn) == "127.0.0.1"
    end
  end

  describe "counted?/3" do
    test "a reader from outside counts" do
      assert Visitor.counted?("203.0.113.5", "Mozilla/5.0 (Macintosh) Safari/605", false)
    end

    test "the admin, a bot and the machine itself do not" do
      refute Visitor.counted?("203.0.113.5", "Mozilla/5.0 Safari/605", true)

      refute Visitor.counted?(
               "203.0.113.5",
               "Googlebot/2.1 (+http://www.google.com/bot.html)",
               false
             )

      refute Visitor.counted?("127.0.0.1", "Mozilla/5.0 Safari/605", false)
      refute Visitor.counted?("::1", "Mozilla/5.0 Safari/605", false)
    end

    test "an address named in EXCLUDED_IPS does not" do
      System.put_env("EXCLUDED_IPS", "198.51.100.7, 198.51.100.8")
      on_exit(fn -> System.delete_env("EXCLUDED_IPS") end)

      refute Visitor.counted?("198.51.100.8", "Mozilla/5.0 Safari/605", false)
      assert Visitor.counted?("198.51.100.9", "Mozilla/5.0 Safari/605", false)
    end
  end
end
