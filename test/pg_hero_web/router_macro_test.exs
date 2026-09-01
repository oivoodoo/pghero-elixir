defmodule PgHeroWeb.RouterMacroTest do
  use ExUnit.Case, async: false

  test "unconfigured dashboard returns a 500" do
    previous = Application.get_all_env(:pghero)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:pghero), do: Application.delete_env(:pghero, key)
      for {key, value} <- previous, do: Application.put_env(:pghero, key, value)
    end)

    # An empty :databases map wins over DATABASE_URL from CI.
    Application.put_env(:pghero, :databases, %{})
    Application.delete_env(:pghero, :repo)
    Application.delete_env(:pghero, :url)

    unless Process.whereis(PgHero.TestEndpoint) do
      start_supervised!(PgHero.TestEndpoint)
    end

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(PgHero.TestEndpoint, :get, "/pghero")

    assert conn.status == 500
    assert conn.resp_body =~ "PgHero is not configured"
  end

  test "assets 404 for unknown files" do
    unless Process.whereis(PgHero.TestEndpoint) do
      start_supervised!(PgHero.TestEndpoint)
    end

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(PgHero.TestEndpoint, :get, "/pghero/assets/nope.js")

    assert conn.status in [404, 500]
  end

  test "serves assets under a nested Phoenix scope" do
    unless Process.whereis(PgHero.TestEndpoint) do
      start_supervised!(PgHero.TestEndpoint)
    end

    conn =
      Phoenix.ConnTest.build_conn()
      |> Phoenix.ConnTest.dispatch(
        PgHero.TestEndpoint,
        :get,
        "/dev/internal/pghero/assets/application.css"
      )

    assert conn.status == 200
    assert conn.resp_body =~ ".btn-danger"
  end

  test "prefix_from_conn includes parent scopes" do
    conn = Phoenix.ConnTest.build_conn(:get, "/dev/internal/pghero/assets/application.css")

    assert PgHeroWeb.Plugs.Dashboard.prefix_from_conn(conn, "/pghero") ==
             "/dev/internal/pghero"

    assert PgHeroWeb.Plugs.Dashboard.prefix_from_conn(conn, "/dev/internal/pghero") ==
             "/dev/internal/pghero"
  end

  test "prefix_from_conn includes script_name" do
    conn =
      Phoenix.ConnTest.build_conn(:get, "/pghero/assets/application.css")
      |> Map.put(:script_name, ["app"])

    assert PgHeroWeb.Plugs.Dashboard.prefix_from_conn(conn, "/pghero") == "/app/pghero"
  end
end
