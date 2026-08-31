defmodule PgHero.Methods.Indexes do
  @moduledoc false

  import PgHero.Query

  def index_hit_rate(db) do
    select_one(db, """
    SELECT
      (sum(idx_blks_hit)) / nullif(sum(idx_blks_hit + idx_blks_read), 0) AS rate
    FROM
      pg_statio_user_indexes
    """)
  end

  def index_caching(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      indexrelname AS index,
      CASE WHEN idx_blks_hit + idx_blks_read = 0 THEN
        0
      ELSE
        ROUND(1.0 * idx_blks_hit / (idx_blks_hit + idx_blks_read), 2)
      END AS hit_rate
    FROM
      pg_statio_user_indexes
    ORDER BY
      3 DESC, 1
    """)
  end

  def index_usage(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      CASE idx_scan
        WHEN 0 THEN 'Insufficient data'
        ELSE (100 * idx_scan / (seq_scan + idx_scan))::text
      END percent_of_times_index_used,
      n_live_tup AS estimated_rows
    FROM
      pg_stat_user_tables
    ORDER BY
      n_live_tup DESC,
      relname ASC
    """)
  end

  def missing_indexes(db) do
    select_all(db, """
    SELECT
      schemaname AS schema,
      relname AS table,
      CASE idx_scan
        WHEN 0 THEN 'Insufficient data'
        ELSE (100 * idx_scan / (seq_scan + idx_scan))::text
      END percent_of_times_index_used,
      n_live_tup AS estimated_rows
    FROM
      pg_stat_user_tables
    WHERE
      idx_scan > 0
      AND (100 * idx_scan / (seq_scan + idx_scan)) < 95
      AND n_live_tup >= 10000
    ORDER BY
      n_live_tup DESC,
      relname ASC
    """)
  end

  def unused_indexes(db, opts \\ []) do
    max_scans = Keyword.get(opts, :max_scans, 50)
    min_size = Keyword.get(opts, :min_size, 0)
    across = Keyword.get(opts, :across, [])

    sql = """
    SELECT
      schemaname AS schema,
      relname AS table,
      indexrelname AS index,
      pg_relation_size(i.indexrelid) AS size_bytes,
      idx_scan as index_scans
    FROM
      pg_stat_user_indexes ui
    INNER JOIN
      pg_index i ON ui.indexrelid = i.indexrelid
    WHERE
      NOT indisunique
      AND idx_scan <= $1
      AND pg_relation_size(i.indexrelid) >= $2
    ORDER BY
      pg_relation_size(i.indexrelid) DESC,
      relname ASC
    """

    result = select_all_size(db, sql, [max_scans, min_size])

    Enum.reduce(across, result, fn database_id, acc ->
      database =
        PgHero.database(database_id) ||
          raise PgHero.Error, message: "Database not found: #{database_id}"

      across_set =
        MapSet.new(unused_indexes(database, max_scans: max_scans), fn v ->
          {v[:schema], v[:index]}
        end)

      Enum.filter(acc, fn v -> MapSet.member?(across_set, {v[:schema], v[:index]}) end)
    end)
  end

  def reset_stats(db) do
    execute(db, "SELECT pg_stat_reset()")
    true
  end

  def last_stats_reset_time(db) do
    select_one(db, """
    SELECT
      pg_stat_get_db_stat_reset_time(oid) AS reset_time
    FROM
      pg_database
    WHERE
      datname = current_database()
    """)
  end

  def invalid_indexes(db, opts \\ []) do
    indexes = opts[:indexes] || indexes(db)

    indexes
    |> Enum.filter(fn i -> not i[:valid] and not i[:creating] end)
    |> Enum.map(fn index -> Map.put(index, :index, index[:name]) end)
  end

  def indexes(db) do
    indexes =
      db
      |> select_all("""
      SELECT
        schemaname AS schema,
        t.relname AS table,
        ix.relname AS name,
        regexp_replace(pg_get_indexdef(i.indexrelid), '^[^\\(]*\\((.*)\\)$', '\\1') AS columns,
        regexp_replace(pg_get_indexdef(i.indexrelid), '.* USING ([^ ]*) \\(.*', '\\1') AS using,
        indisunique AS unique,
        indisprimary AS primary,
        indisvalid AS valid,
        indexprs::text,
        indpred::text,
        pg_get_indexdef(i.indexrelid) AS definition
      FROM
        pg_index i
      INNER JOIN
        pg_class t ON t.oid = i.indrelid
      INNER JOIN
        pg_class ix ON ix.oid = i.indexrelid
      LEFT JOIN
        pg_stat_user_indexes ui ON ui.indexrelid = i.indexrelid
      WHERE
        schemaname IS NOT NULL
      ORDER BY
        1, 2
      """)
      |> Enum.map(fn v ->
        columns =
          v[:columns]
          |> to_string()
          |> String.replace(") WHERE (", " WHERE ")
          |> String.split(", ")
          |> Enum.map(&unquote_ident/1)

        Map.put(v, :columns, columns)
      end)

    invalid = Enum.filter(indexes, fn i -> not i[:valid] end)

    if invalid == [] do
      indexes
    else
      create_index_queries =
        db
        |> PgHero.Methods.Queries.running_queries()
        |> Enum.filter(fn q ->
          q[:query] && Regex.match?(~r/\s*CREATE\s+INDEX\s+CONCURRENTLY\s+/i, q[:query])
        end)

      Enum.map(indexes, fn index ->
        if index[:valid] do
          index
        else
          creating =
            Enum.any?(create_index_queries, fn q ->
              String.contains?(q[:query], index[:table]) and
                Enum.all?(index[:columns], fn c -> String.contains?(q[:query], c) end)
            end)

          Map.put(index, :creating, creating)
        end
      end)
    end
  end

  def duplicate_indexes(db, opts \\ []) do
    indexes = opts[:indexes] || indexes(db)
    indexes_by_table = Enum.group_by(indexes, fn i -> {i[:schema], i[:table]} end)

    indexes
    |> Enum.filter(fn i -> i[:valid] and not i[:primary] and not i[:unique] end)
    |> Enum.flat_map(fn index ->
      covering_index =
        (indexes_by_table[{index[:schema], index[:table]}] || [])
        |> Enum.find(fn i ->
          i[:valid] and i[:name] != index[:name] and
            index_covers?(i[:columns], index[:columns]) and
            i[:using] == index[:using] and
            i[:indexprs] == index[:indexprs] and
            i[:indpred] == index[:indpred]
        end)

      if covering_index &&
           (covering_index[:columns] != index[:columns] or index[:name] > covering_index[:name] or
              covering_index[:primary] or covering_index[:unique]) do
        [%{unneeded_index: index, covering_index: covering_index}]
      else
        []
      end
    end)
    |> Enum.sort_by(fn i -> {i.unneeded_index[:table], i.unneeded_index[:columns]} end)
  end

  def index_bloat(db, opts \\ []) do
    min_size = opts[:min_size] || PgHero.Database.index_bloat_bytes(db)

    sql = """
    WITH btree_index_atts AS (
      SELECT
        nspname, relname, reltuples, relpages, indrelid, relam,
        regexp_split_to_table(indkey::text, ' ')::smallint AS attnum,
        indexrelid as index_oid
      FROM
        pg_index
      JOIN
        pg_class ON pg_class.oid = pg_index.indexrelid
      JOIN
        pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      JOIN
        pg_am ON pg_class.relam = pg_am.oid
      WHERE
        pg_am.amname = 'btree'
    ),
    index_item_sizes AS (
      SELECT
        i.nspname,
        i.relname,
        i.reltuples,
        i.relpages,
        i.relam,
        (quote_ident(s.schemaname) || '.' || quote_ident(s.tablename))::regclass AS starelid,
        a.attrelid AS table_oid, index_oid,
        current_setting('block_size')::numeric AS bs,
        CASE
          WHEN version() ~ 'mingw32' OR version() ~ '64-bit' THEN 8
          ELSE 4
        END AS maxalign,
        24 AS pagehdr,
        CASE WHEN max(coalesce(s.null_frac,0)) = 0
          THEN 2
          ELSE 6
        END AS index_tuple_hdr,
        sum( (1-coalesce(s.null_frac, 0)) * coalesce(s.avg_width, 2048) ) AS nulldatawidth
      FROM
        pg_attribute AS a
      JOIN
        pg_stats AS s ON (quote_ident(s.schemaname) || '.' || quote_ident(s.tablename))::regclass=a.attrelid AND s.attname = a.attname
      JOIN
        btree_index_atts AS i ON i.indrelid = a.attrelid AND a.attnum = i.attnum
      WHERE
        a.attnum > 0
      GROUP BY
        1, 2, 3, 4, 5, 6, 7, 8, 9
    ),
    index_aligned AS (
      SELECT
        maxalign,
        bs,
        nspname,
        relname AS index_name,
        reltuples,
        relpages,
        relam,
        table_oid,
        index_oid,
        ( 2 +
          maxalign - CASE
            WHEN index_tuple_hdr%maxalign = 0 THEN maxalign
            ELSE index_tuple_hdr%maxalign
          END
        + nulldatawidth + maxalign - CASE
          WHEN nulldatawidth::integer%maxalign = 0 THEN maxalign
          ELSE nulldatawidth::integer%maxalign
        END
        )::numeric AS nulldatahdrwidth, pagehdr
      FROM
        index_item_sizes AS s1
    ),
    otta_calc AS (
      SELECT
        bs,
        nspname,
        table_oid,
        index_oid,
        index_name,
        relpages,
        coalesce(
          ceil((reltuples*(4+nulldatahdrwidth))/(bs-pagehdr::float)) +
          CASE WHEN am.amname IN ('hash','btree') THEN 1 ELSE 0 END , 0
        ) AS otta
      FROM
        index_aligned AS s2
      LEFT JOIN
        pg_am am ON s2.relam = am.oid
    ),
    raw_bloat AS (
      SELECT
        nspname,
        c.relname AS table_name,
        index_name,
        bs*(sub.relpages)::bigint AS totalbytes,
        CASE
          WHEN sub.relpages <= otta THEN 0
          ELSE bs*(sub.relpages-otta)::bigint END
          AS wastedbytes,
        CASE
          WHEN sub.relpages <= otta
          THEN 0 ELSE bs*(sub.relpages-otta)::bigint * 100 / (bs*(sub.relpages)::bigint) END
          AS realbloat,
        pg_relation_size(sub.table_oid) as table_bytes,
        stat.idx_scan as index_scans,
        stat.indexrelid
      FROM
        otta_calc AS sub
      JOIN
        pg_class AS c ON c.oid=sub.table_oid
      JOIN
        pg_stat_user_indexes AS stat ON sub.index_oid = stat.indexrelid
    )
    SELECT
      nspname AS schema,
      table_name AS table,
      index_name AS index,
      wastedbytes AS bloat_bytes,
      totalbytes AS index_bytes,
      pg_get_indexdef(rb.indexrelid) AS definition,
      indisprimary AS primary
    FROM
      raw_bloat rb
    INNER JOIN
      pg_index i ON i.indexrelid = rb.indexrelid
    WHERE
      wastedbytes >= $1
    ORDER BY
      wastedbytes DESC,
      index_name
    """

    select_all(db, sql, [min_size])
  end

  def index_covers?(indexed_columns, columns) do
    Enum.take(indexed_columns, length(columns)) == columns
  end
end
