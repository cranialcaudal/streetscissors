defmodule WebWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use WebWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint WebWeb.Endpoint

      use WebWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import WebWeb.ConnCase
      import Swoosh.TestAssertions
    end
  end

  setup tags do
    Web.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  The connection with the admin's session, as a correct password leaves it
  (`WebWeb.AdminSessionController`).

      conn = log_in_admin(conn)

  Every test that needs the admin logs in through here, so the flag is
  spelled once: the boolean `true`, which is what the site's own checks read.
  """
  def log_in_admin(conn), do: Plug.Test.init_test_session(conn, %{"admin_user" => true})
end
