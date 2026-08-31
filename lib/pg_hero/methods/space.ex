defmodule PgHero.Methods.Space do
  @moduledoc false

  import PgHero.Query

  def database_size(db) do
    PgHero.Pretty.size(select_one(db, "SELECT pg_database_size(current_database())"))
  end

  def relation_sizes(db) do
    select_all_size(db, """
    SELECT
      n.nspname AS schema,
      c.relname AS relation,
      CASE c.relkind WHEN 'r' THEN 'table' WHEN 'm' then 'matview' ELSE 'index' END AS type,
      pg_table_size(c.oid) AS size_bytes
    FROM
      pg_class c
    LEFT JOIN
      pg_namespace n ON n.oid = c.relnamespace
    WHERE
      n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname !~ '^pg_toast'
      AND c.relkind IN ('r', 'm', 'i')
    ORDER BY
      pg_table_size(c.oid) DESC,
      2 ASC
    """)
  end

  def table_sizes(db) do
    select_all_size(db, """
    SELECT
      n.nspname AS schema,
      c.relname AS table,
      pg_total_relation_size(c.oid) AS size_bytes
    FROM
      pg_class c
    LEFT JOIN
      pg_namespace n ON n.oid = c.relnamespace
    WHERE
      n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname !~ '^pg_toast'
      AND c.relkind = 'r'
    ORDER BY
      pg_total_relation_size(c.oid) DESC,
      2 ASC
    """)
  end

  def space_growth(db, opts \\ []) do
    unless space_stats_enabled?(db),
      do: raise(PgHero.NotEnabled, message: "Space stats not enabled")

    days = Keyword.get(opts, :days, 7)
    relation_sizes = opts[:relation_sizes] || relation_sizes(db)
    sizes = Map.new(relation_sizes, fn r -> {{r[:schema], r[:relation]}, r[:size_bytes]} end)
    start_at = DateTime.add(DateTime.utc_now(), -days * 24 * 3600, :second)

    sql = """
    WITH t AS (
      SELECT
        schema,
        relation,
        array_agg(size ORDER BY captured_at) AS sizes
      FROM
        pghero_space_stats
      WHERE
        database = $1
        AND captured_at >= $2
      GROUP BY
        1, 2
    )
    SELECT
      schema,
      relation,
      sizes[1] AS size_bytes
    FROM
      t
    ORDER BY
      1, 2
    """

    db
    |> select_all(sql, [db.id, start_at], stats: true)
    |> Enum.map(fn r ->
      relation = {r[:schema], r[:relation]}

      r
      |> maybe_put_growth(sizes[relation])
      |> Map.delete(:size_bytes)
    end)
  end

  def relation_space_stats(db, relation, opts \\ []) do
    unless space_stats_enabled?(db),
      do: raise(PgHero.NotEnabled, message: "Space stats not enabled")

    schema = Keyword.get(opts, :schema, "public")
    sizes = Map.new(relation_sizes(db), fn r -> {{r[:schema], r[:relation]}, r[:size_bytes]} end)
    start_at = DateTime.add(DateTime.utc_now(), -30 * 24 * 3600, :second)

    sql = """
    SELECT
      captured_at,
      size AS size_bytes
    FROM
      pghero_space_stats
    WHERE
      database = $1
      AND captured_at >= $2
      AND schema = $3
      AND relation = $4
    ORDER BY
      1 ASC
    """

    stats = select_all(db, sql, [db.id, start_at, schema, relation], stats: true)

    stats ++
      [
        %{
          captured_at: DateTime.utc_now(),
          size_bytes: sizes[{schema, relation}] || 0
        }
      ]
  end

  def capture_space_stats(db) do
    now = DateTime.utc_now()
    values = relation_sizes(db)

    if values != [] do
      placeholders =
        values
        |> Enum.with_index()
        |> Enum.map_join(", ", fn {_rs, i} ->
          base = i * 5
          "($#{base + 1}, $#{base + 2}, $#{base + 3}, $#{base + 4}, $#{base + 5})"
        end)

      params =
        Enum.flat_map(values, fn rs ->
          [db.id, rs[:schema], rs[:relation], trunc(rs[:size_bytes] || 0), now]
        end)

      execute(
        db,
        "INSERT INTO pghero_space_stats (database, schema, relation, size, captured_at) VALUES #{placeholders}",
        params,
        stats: true
      )
    end

    true
  end

  def clean_space_stats(db, opts \\ []) do
    before = opts[:before] || DateTime.add(DateTime.utc_now(), -90 * 24 * 3600, :second)

    execute(
      db,
      "DELETE FROM pghero_space_stats WHERE database = $1 AND captured_at < $2",
      [db.id, before],
      stats: true
    )

    true
  end

  def space_stats_enabled?(db) do
    PgHero.Methods.Basic.table_exists?(db, "pghero_space_stats", stats: true)
  end

  defp maybe_put_growth(row, nil), do: row
  defp maybe_put_growth(row, current), do: Map.put(row, :growth_bytes, current - row[:size_bytes])
end
