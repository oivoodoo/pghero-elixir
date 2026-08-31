defmodule PgHero.Methods.Maintenance do
  @moduledoc false

  import PgHero.Query

  def transaction_id_danger(db, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 10_000_000)
    max_value = Keyword.get(opts, :max_value, 2_146_483_648)

    sql = """
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      $1::bigint - GREATEST(AGE(c.relfrozenxid), AGE(t.relfrozenxid)) AS transactions_left
    FROM
      pg_class c
    INNER JOIN
      pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN
      pg_class t ON c.reltoastrelid = t.oid
    WHERE
      c.relkind = 'r'
      AND ($1::bigint - GREATEST(AGE(c.relfrozenxid), AGE(t.relfrozenxid))) < $2
    ORDER BY
     3, 1, 2
    """

    select_all(db, sql, [max_value, threshold])
  end

  def autovacuum_danger(db) do
    max_value =
      db |> select_one("SHOW autovacuum_freeze_max_age") |> to_string() |> String.to_integer()

    transaction_id_danger(db, threshold: 2_000_000, max_value: max_value)
  end

  def vacuum_progress(db) do
    select_all(db, """
    SELECT
      pid,
      phase
    FROM
      pg_stat_progress_vacuum
    WHERE
      datname = current_database()
    """)
  end

  def maintenance_info(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      last_vacuum,
      last_autovacuum,
      last_analyze,
      last_autoanalyze,
      n_dead_tup AS dead_rows,
      n_live_tup AS live_rows
    FROM
      pg_stat_user_tables
    ORDER BY
      1, 2
    """)
  end

  def analyze(db, table, opts \\ []) do
    verbose = if opts[:verbose], do: "VERBOSE ", else: ""
    execute(db, "ANALYZE #{verbose}#{quote_table_name(table)}")
    true
  end

  def analyze_tables(db, opts \\ []) do
    min_size = opts[:min_size]
    tables = opts[:table] || opts[:tables]

    db
    |> PgHero.Methods.Tables.table_stats(table: tables)
    |> Enum.reject(fn s -> s[:schema] in ["information_schema", "pg_catalog"] end)
    |> Enum.filter(fn s -> is_nil(min_size) or s[:size_bytes] > min_size end)
    |> Enum.map(fn stats ->
      success =
        try do
          with_transaction(
            db,
            fn conn ->
              analyze(%{db | conn: conn}, "#{stats[:schema]}.#{stats[:table]}",
                verbose: opts[:verbose]
              )
            end,
            lock_timeout: 5000,
            statement_timeout: 120_000
          )

          true
        rescue
          e in Postgrex.Error ->
            IO.warn(Exception.message(e))
            false
        end

      Map.merge(Map.take(stats, [:schema, :table]), %{success: success})
    end)
  end
end
