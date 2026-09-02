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
    error =
      assert_raise Postgrex.Error, fn ->
        PgHero.Database.explain(db, "SELECT 1; SELECT 2")
      end

    assert Exception.message(error) =~ "Unsafe statement"
  end

  test "explains parameterized queries without ArgumentError", %{database: db} do
    sql = ~s[SELECT relname FROM pg_class WHERE relname = $1]

    result =
      try do
        opts =
          if PgHero.Database.server_version_num(db) >= 160_000,
            do: [generic_plan: true],
            else: []

        {:ok, PgHero.Database.explain(db, sql, opts)}
      rescue
        e in ArgumentError -> {:argument_error, Exception.message(e)}
        e in Postgrex.Error -> {:postgrex_error, Exception.message(e)}
      end

    refute match?({:argument_error, _}, result),
           "EXPLAIN with $1 must not raise ArgumentError, got: #{inspect(result)}"

    if PgHero.Database.server_version_num(db) >= 160_000 do
      assert {:ok, plan} = result
      assert is_binary(plan)
      assert plan =~ "pg_class"
    else
      assert {:postgrex_error, message} = result
      assert message =~ "parameter"
    end
  end

  test "explains queries with multiple bind parameters", %{database: db} do
    sql = """
    SELECT relname FROM pg_class
    WHERE relname = $1 AND relnamespace = $2 AND relkind = $3
    """

    if PgHero.Database.server_version_num(db) >= 160_000 do
      plan = PgHero.Database.explain(db, sql, generic_plan: true)
      assert is_binary(plan)
      assert plan =~ "pg_class"
    else
      assert_raise Postgrex.Error, fn ->
        PgHero.Database.explain(db, sql)
      end
    end
  end

  test "explains joins with jsonb operators and bind params", %{database: db} do
    PgHero.Query.execute(db, """
    CREATE TABLE IF NOT EXISTS pghero_explain_parents (
      id uuid PRIMARY KEY,
      owner_id uuid,
      meta jsonb
    )
    """)

    PgHero.Query.execute(db, """
    CREATE TABLE IF NOT EXISTS pghero_explain_children (
      id uuid PRIMARY KEY,
      payload jsonb,
      parent_name text,
      parent_id uuid REFERENCES pghero_explain_parents(id),
      inserted_at timestamp,
      updated_at timestamp
    )
    """)

    sql = """
    SELECT c."id", c."payload", c."parent_name", c."parent_id",
           c."inserted_at", c."updated_at"
    FROM "pghero_explain_children" AS c
    INNER JOIN "pghero_explain_parents" AS p ON c."parent_id" = p."id"
    WHERE (((c."parent_name" = $1) AND (p."owner_id" = $2))
       AND p."meta" ->> 'group_id' = $3)
    """

    if PgHero.Database.server_version_num(db) >= 160_000 do
      plan = PgHero.Database.explain(db, sql, generic_plan: true)
      assert is_binary(plan)
      assert plan =~ "pghero_explain_children"
    else
      assert_raise Postgrex.Error, fn ->
        PgHero.Database.explain(db, sql)
      end
    end
  end
end
