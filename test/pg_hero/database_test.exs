defmodule PgHero.DatabaseTest do
  use ExUnit.Case, async: false

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

    {:ok, database: PgHero.database("primary")}
  end

  test "server version is postgres 14+", %{database: db} do
    assert PgHero.Database.server_version_num(db) >= 140_000
  end

  test "lists connections", %{database: db} do
    connections = PgHero.Database.connections(db)
    assert is_list(connections)
    assert hd(connections)[:pid]
  end

  test "reports relation sizes", %{database: db} do
    PgHero.Query.execute(db, "CREATE TABLE IF NOT EXISTS pghero_size_test (id integer)")
    sizes = PgHero.Database.relation_sizes(db)
    assert Enum.any?(sizes, fn row -> row[:relation] == "pghero_size_test" end)
    assert Enum.all?(sizes, fn row -> is_binary(row[:size]) and is_integer(row[:size_bytes]) end)
  end

  test "reads settings", %{database: db} do
    settings = PgHero.Database.settings(db)
    assert settings[:max_connections]
    assert settings[:shared_buffers]
  end

  test "maintenance info", %{database: db} do
    info = PgHero.Database.maintenance_info(db)
    assert is_list(info)
  end

  test "explain a simple select", %{database: db} do
    plan = PgHero.Database.explain(db, "SELECT 1")
    assert is_binary(plan)
    assert plan =~ "Result" or plan =~ "One-Time Filter" or plan =~ "SELECT"
  end

  test "rejects unsafe explain statements", %{database: db} do
    assert_raise Postgrex.Error, fn ->
      PgHero.Database.explain(db, "SELECT 1; SELECT 2")
    end
  end
end
