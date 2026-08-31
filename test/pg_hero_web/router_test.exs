defmodule PgHeroWeb.RouterTest do
  use PgHeroWeb.ConnCase, async: false

  @moduletag :integration
  @moduletag skip: PgHero.Integration.skip_reason()

  setup do
    url = PgHero.Integration.url()
    Application.put_env(:pghero, :url, url)
    Application.delete_env(:pghero, :repo)
    Application.delete_env(:pghero, :databases)

    start_supervised!(
      {Postgrex,
       Keyword.merge(PgHero.Integration.postgrex_opts(url),
         name: PgHero.Config.connection_name("primary")
       )}
    )

    unless Process.whereis(PgHero.TestEndpoint) do
      start_supervised!(PgHero.TestEndpoint)
    end

    :ok
  end

  test "serves overview", %{conn: conn} do
    conn = get(conn, "/pghero")
    assert html_response(conn, 200) =~ "PgHero"
    assert html_response(conn, 200) =~ "Overview"

    assert html_response(conn, 200) =~ "Connections healthy" or
             html_response(conn, 200) =~ "connections"
  end

  test "serves space, connections, live queries, maintenance, explain, and tune", %{conn: conn} do
    for path <- [
          "/pghero/space",
          "/pghero/connections",
          "/pghero/live_queries",
          "/pghero/maintenance",
          "/pghero/explain",
          "/pghero/tune"
        ] do
      conn = get(conn, path)
      assert html_response(conn, 200)
    end
  end

  test "serves assets", %{conn: conn} do
    conn = get(conn, "/pghero/assets/application.css")
    assert response(conn, 200) =~ ".btn-danger"
  end

  test "explains a query", %{conn: conn} do
    conn = post(conn, "/pghero/explain", %{"query" => "SELECT 1", "commit" => "Explain"})
    assert html_response(conn, 200) =~ "Explain"
  end
end
