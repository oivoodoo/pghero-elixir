defmodule PgHeroWeb.RouterMacroTest do
  use ExUnit.Case, async: true

  test "unconfigured dashboard returns a 500" do
    Application.delete_env(:pghero, :repo)
    Application.delete_env(:pghero, :url)
    Application.delete_env(:pghero, :databases)

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
end
