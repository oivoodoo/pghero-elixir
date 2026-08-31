defmodule PgHero.Methods.Tables do
  @moduledoc false

  import PgHero.Query

  def table_hit_rate(db) do
    select_one(db, """
    SELECT
      sum(heap_blks_hit) / nullif(sum(heap_blks_hit) + sum(heap_blks_read), 0) AS rate
    FROM
      pg_statio_user_tables
    """)
  end

  def table_caching(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      CASE WHEN heap_blks_hit + heap_blks_read = 0 THEN
        0
      ELSE
        ROUND(1.0 * heap_blks_hit / (heap_blks_hit + heap_blks_read), 2)
      END AS hit_rate
    FROM
      pg_statio_user_tables
    ORDER BY
      2 DESC, 1
    """)
  end

  def unused_tables(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      n_live_tup AS estimated_rows
    FROM
      pg_stat_user_tables
    WHERE
      idx_scan = 0
    ORDER BY
      n_live_tup DESC,
      relname ASC
    """)
  end

  def table_stats(db, opts \\ []) do
    schema = opts[:schema]
    table = opts[:table] || opts[:tables]

    {schema_sql, params, next} =
      if schema do
        {"AND nspname = $1", [schema], 2}
      else
        {"", [], 1}
      end

    {table_sql, params} =
      if table do
        tables = List.wrap(table)

        placeholders =
          tables |> Enum.with_index(next) |> Enum.map_join(", ", fn {_t, i} -> "$#{i}" end)

        {"AND relname IN (#{placeholders})", params ++ tables}
      else
        {"", params}
      end

    sql = """
    SELECT
      nspname AS schema,
      relname AS table,
      reltuples::bigint AS estimated_rows,
      pg_total_relation_size(pg_class.oid) AS size_bytes
    FROM
      pg_class
    INNER JOIN
      pg_namespace ON pg_namespace.oid = pg_class.relnamespace
    WHERE
      relkind = 'r'
      #{schema_sql}
      #{table_sql}
    ORDER BY
      1, 2
    """

    select_all(db, sql, params)
  end
end
