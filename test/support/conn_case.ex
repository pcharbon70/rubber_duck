defmodule RubberDuckWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint RubberDuckWeb.Endpoint

      use RubberDuckWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import RubberDuckWeb.ConnCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(RubberDuck.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    
    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:secret_key_base, RubberDuckWeb.Endpoint.config(:secret_key_base))
    
    {:ok, conn: conn}
  end

  @doc """
  Setup helper that logs in users.

      setup :log_in_user

  It stores the user in the connection.
  """
  def log_in_user(%{conn: conn, user: user}) do
    conn = log_in_user(conn, user)
    %{conn: conn}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user) do
    # For tests, we'll simulate authentication by directly setting the user
    # in the session and assigns, similar to how the authentication system works
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
    |> Plug.Conn.assign(:current_user, user)
  end
end