defmodule PgHero.Methods.QueryStats do
  @moduledoc false

  import PgHero.Query

  def query_stats(db, opts \\ []) do
    current? = Keyword.get(opts, :current, true)
    historical? = Keyword.get(opts, :historical, false)
    limit = Keyword.get(opts, :limit, 100)
    sort = Keyword.get(opts, :sort) || "total_time"
    user = opts[:user]
    query_hash = opts[:query_hash]
    start_at = opts[:start_at]
    end_at = opts[:end_at]
    min_average_time = opts[:min_average_time]
    min_calls = opts[:min_calls]

    unless sort in ["total_time", "average_time", "calls"] do
      raise ArgumentError, "Invalid sort"
    end

    {current_stats, current_total_time} =
      if not current? or
           (historical? and end_at && DateTime.compare(to_dt(end_at), DateTime.utc_now()) == :lt) do
        {[], 0}
      else
        current_query_stats(db, limit: limit, sort: sort, user: user, query_hash: query_hash)
      end

    {historical_stats, historical_total_time} =
      if historical? and historical_query_stats_enabled?(db) do
        historical_query_stats(db,
          limit: limit,
          sort: sort,
          user: user,
          query_hash: query_hash,
          start_at: start_at,
          end_at: end_at
        )
      else
        {[], 0}
      end

    query_stats =
      (current_stats ++ historical_stats)
      |> Enum.group_by(fn q -> {q[:query_hash], q[:user]} end)
      |> combine_query_stats()
      |> Enum.map(fn query ->
        Map.put(query, :average_time, query[:total_time] / max(query[:calls], 1))
      end)

    query_stats =
      if is_nil(user) and is_nil(query_hash) do
        all_total = current_total_time + historical_total_time

        Enum.map(query_stats, fn query ->
          percent = if all_total > 0, do: query[:total_time] * 100.0 / all_total, else: 0
          Map.put(query, :total_percent, percent)
        end)
      else
        query_stats
      end

    sort_key = String.to_existing_atom(sort)

    query_stats
    |> Enum.sort_by(fn q -> -(q[sort_key] || 0) end)
    |> Enum.take(limit)
    |> maybe_reject_min_average(min_average_time)
    |> maybe_reject_min_calls(min_calls)
  end

  def query_stats_available?(db) do
    select_one(
      db,
      "SELECT COUNT(*) AS count FROM pg_available_extensions WHERE name = 'pg_stat_statements'"
    ) > 0
  end

  def query_stats_enabled?(db), do: query_stats_readable?(db)

  def query_stats_extension_enabled?(db) do
    select_one(
      db,
      "SELECT COUNT(*) AS count FROM pg_extension WHERE extname = 'pg_stat_statements'"
    ) > 0
  end

  def query_stats_readable?(db) do
    select_all(db, "SELECT * FROM pg_stat_statements LIMIT 1")
    true
  rescue
    _ in Postgrex.Error -> false
  end

  def enable_query_stats(db) do
    execute(db, "CREATE EXTENSION IF NOT EXISTS pg_stat_statements")
    true
  end

  def disable_query_stats(db) do
    execute(db, "DROP EXTENSION IF EXISTS pg_stat_statements")
    true
  end

  def reset_query_stats(db, opts \\ []) do
    database = PgHero.Methods.Basic.database_name(db)
    database_id = select_one(db, "SELECT oid FROM pg_database WHERE datname = $1", [database])
    if is_nil(database_id), do: raise(PgHero.Error, message: "Database not found: #{database}")

    user_id =
      case opts[:user] do
        nil ->
          0

        user ->
          user_id = select_one(db, "SELECT usesysid FROM pg_user WHERE usename = $1", [user])
          if is_nil(user_id), do: raise(PgHero.Error, message: "User not found: #{user}")
          user_id
      end

    query_id =
      case opts[:query_hash] do
        nil ->
          0

        query_hash ->
          query_id = to_integer(query_hash)
          if query_id == 0, do: raise(PgHero.Error, message: "Invalid query hash: #{query_hash}")
          query_id
      end

    execute(db, "SELECT pg_stat_statements_reset($1, $2, $3)", [user_id, database_id, query_id])
    true
  rescue
    e in Postgrex.Error ->
      if opts[:raise_errors], do: reraise(e, __STACKTRACE__), else: false
  end

  def historical_query_stats_enabled?(db) do
    queries_table_exists?(db) and query_stats_table_exists?(db) and
      PgHero.Database.capture_query_stats?(db)
  end

  def queries_table_exists?(db),
    do: PgHero.Methods.Basic.table_exists?(db, "pghero_queries", stats: true)

  def query_stats_table_exists?(db),
    do: PgHero.Methods.Basic.table_exists?(db, "pghero_query_stats", stats: true)

  def capture_query_stats(db, opts \\ []) do
    captured_at = DateTime.utc_now()
    stats = query_stats(db, limit: 100)

    if stats != [] and
         reset_query_stats(db, raise_errors: Keyword.get(opts, :raise_errors, false)) do
      insert_query_stats(db, stats, captured_at)
    end
  end

  def clean_query_stats(db, opts \\ []) do
    before = opts[:before] || DateTime.add(DateTime.utc_now(), -14 * 24 * 3600, :second)

    execute(
      db,
      "DELETE FROM pghero_query_stats WHERE database = $1 AND captured_at < $2",
      [db.id, before],
      stats: true
    )

    true
  end

  def slow_queries(db, opts \\ []) do
    stats = opts[:query_stats] || query_stats(db, Keyword.delete(opts, :query_stats))
    min_calls = PgHero.Database.slow_query_calls(db)
    min_ms = PgHero.Database.slow_query_ms(db)

    Enum.filter(stats, fn q ->
      (q[:calls] || 0) >= min_calls and (q[:average_time] || 0) >= min_ms
    end)
  end

  def query_hash_stats(db, query_hash, opts \\ []) do
    unless historical_query_stats_enabled?(db) do
      raise PgHero.NotEnabled, message: "Query hash stats not enabled"
    end

    current? = Keyword.get(opts, :current, true)
    user = opts[:user]
    start_at = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    {user_sql, params} =
      if user do
        {"AND \"user\" = $4", [db.id, start_at, query_hash, user]}
      else
        {"", [db.id, start_at, query_hash]}
      end

    sql = """
    SELECT
      captured_at,
      total_time,
      calls,
      (SELECT regexp_matches(pghero_queries.query, '.*/\\*(.+?)\\*/'))[1] AS origin
    FROM
      pghero_query_stats
    INNER JOIN
      pghero_queries ON pghero_queries.id = pghero_query_stats.query_id
    WHERE
      database = $1
      AND captured_at >= $2
      AND query_hash = $3
      #{user_sql}
    ORDER BY
      1 ASC
    """

    stats = select_all(db, sql, params, stats: true)

    stats =
      if current? do
        captured_at = DateTime.utc_now()

        {current_stats, _} =
          current_query_stats(db, query_hash: query_hash, user: user, origin: true)

        stats ++
          Enum.map(current_stats, fn r ->
            %{
              captured_at: captured_at,
              total_time: r[:total_time],
              calls: r[:calls],
              origin: r[:origin]
            }
          end)
      else
        stats
      end

    Enum.map(stats, fn query ->
      Map.put(query, :average_time, query[:total_time] / max(query[:calls], 1))
    end)
  end

  def explainable?(db, query) do
    String.match?(query || "", ~r/select/i) and
      (PgHero.Database.server_version_num(db) >= 160_000 or not String.contains?(query, "$1"))
  end

  defp current_query_stats(db, opts) do
    unless query_stats_enabled?(db),
      do: raise(PgHero.NotEnabled, message: "Query stats not enabled")

    limit = Keyword.get(opts, :limit, 100)
    sort = Keyword.get(opts, :sort) || "total_time"
    user = opts[:user]
    query_hash = opts[:query_hash]
    origin? = Keyword.get(opts, :origin, false)

    {user_sql, params, next} = optional_eq("AND rolname", user, [])
    {hash_sql, params, next} = optional_eq("AND queryid", query_hash, params, next)
    params = params ++ [limit]

    average_select =
      if sort == "average_time",
        do: "(total_plan_time + total_exec_time) / calls AS average_time,",
        else: ""

    origin_select =
      if origin?, do: "(SELECT regexp_matches(query, '.*/\\*(.+?)\\*/'))[1] AS origin,", else: ""

    origin_null = if origin?, do: "NULL, ", else: ""

    sql = """
    WITH query_stats AS (
      SELECT
        LEFT(query, 10000) AS query,
        queryid AS query_hash,
        rolname AS user,
        total_plan_time + total_exec_time AS total_time,
        #{average_select}
        calls
      FROM
        pg_stat_statements
      INNER JOIN
        pg_database ON pg_database.oid = pg_stat_statements.dbid
      INNER JOIN
        pg_roles ON pg_roles.oid = pg_stat_statements.userid
      WHERE
        calls > 0 AND
        pg_database.datname = current_database()
        #{user_sql}
        #{hash_sql}
    )
    (
      SELECT
        query,
        #{origin_select}
        query_hash,
        query_stats.user,
        total_time,
        calls
      FROM
        query_stats
      ORDER BY
        #{quote_ident(sort)} DESC
      LIMIT $#{next}
    ) UNION ALL (
      SELECT NULL, #{origin_null}NULL, NULL, SUM(total_time), NULL FROM query_stats
    )
    """

    result = select_all(db, sql, params)
    {total, result} = List.pop_at(result, -1)
    {result, (total && total[:total_time]) || 0}
  end

  defp historical_query_stats(db, opts) do
    unless historical_query_stats_enabled?(db) do
      raise PgHero.NotEnabled, message: "Historical query stats not enabled"
    end

    limit = Keyword.get(opts, :limit, 100)
    sort = Keyword.get(opts, :sort) || "total_time"
    user = opts[:user]
    query_hash = opts[:query_hash]
    start_at = opts[:start_at]
    end_at = opts[:end_at]

    params = [db.id]
    next = 2

    {start_sql, params, next} = optional_cmp("AND captured_at >=", start_at, params, next)
    {end_sql, params, next} = optional_cmp("AND captured_at <=", end_at, params, next)
    {user_sql, params, next} = optional_eq("AND \"user\"", user, params, next)

    {hash_sql, params, next} =
      if query_hash do
        {"AND query_hash = $#{next}", params ++ [query_hash], next + 1}
      else
        {"AND query_hash IS NOT NULL", params, next}
      end

    params = params ++ [limit]

    average_select =
      if sort == "average_time", do: "SUM(total_time) / SUM(calls) AS average_time,", else: ""

    sql = """
    WITH query_stats AS (
      SELECT
        query_hash,
        "user",
        query_id,
        SUM(total_time) AS total_time,
        SUM(calls) AS calls
      FROM
        pghero_query_stats
      WHERE
        database = $1
        #{start_sql}
        #{end_sql}
        #{user_sql}
        #{hash_sql}
      GROUP BY
        1, 2, 3
    ),
    grouped_query_stats AS (
      SELECT
        query_hash,
        "user",
        (array_agg(query_id ORDER BY total_time DESC))[1] AS query_id,
        SUM(total_time) AS total_time,
        #{average_select}
        SUM(calls) AS calls
      FROM
        query_stats
      GROUP BY
        1, 2
      ORDER BY
        #{quote_ident(sort)} DESC
      LIMIT $#{next}
    )
    (
      SELECT
        query_hash,
        "user",
        query,
        total_time,
        calls
      FROM
        grouped_query_stats
      INNER JOIN
        pghero_queries ON pghero_queries.id = grouped_query_stats.query_id
      ORDER BY
        #{quote_ident(sort)} DESC
    ) UNION ALL (
      SELECT NULL, NULL, NULL, SUM(total_time), NULL FROM query_stats
    )
    """

    result = select_all(db, sql, params, stats: true)
    {total, result} = List.pop_at(result, -1)
    {result, (total && total[:total_time]) || 0}
  end

  defp combine_query_stats(grouped_stats) do
    Enum.map(grouped_stats, fn {_, stats} ->
      %{
        query: first_present(stats, :query),
        user: first_present(stats, :user),
        query_hash: first_present(stats, :query_hash),
        total_time: Enum.reduce(stats, 0, fn s, acc -> acc + (s[:total_time] || 0) end),
        calls: Enum.reduce(stats, 0, fn s, acc -> acc + trunc(s[:calls] || 0) end)
      }
    end)
  end

  defp insert_query_stats(db, query_stats, captured_at) do
    query_ids = add_queries(db, Enum.map(query_stats, & &1[:query]))

    values =
      Enum.map(query_stats, fn qs ->
        %{
          database: db.id,
          user: qs[:user],
          query_id: Map.fetch!(query_ids, qs[:query]),
          query_hash: qs[:query_hash],
          total_time: qs[:total_time],
          calls: qs[:calls],
          captured_at: captured_at
        }
      end)

    if values != [] do
      placeholders =
        values
        |> Enum.with_index()
        |> Enum.map_join(", ", fn {_v, i} ->
          base = i * 7

          "($#{base + 1}, $#{base + 2}, $#{base + 3}, $#{base + 4}, $#{base + 5}, $#{base + 6}, $#{base + 7})"
        end)

      params =
        Enum.flat_map(values, fn v ->
          [v.database, v.user, v.query_id, v.query_hash, v.total_time, v.calls, v.captured_at]
        end)

      execute(
        db,
        """
        INSERT INTO pghero_query_stats (database, "user", query_id, query_hash, total_time, calls, captured_at)
        VALUES #{placeholders}
        """,
        params,
        stats: true
      )
    end
  end

  defp add_queries(db, queries) do
    queries = Enum.uniq(queries)

    existing =
      if queries == [] do
        %{}
      else
        placeholders =
          queries |> Enum.with_index(1) |> Enum.map_join(", ", fn {_q, i} -> "$#{i}" end)

        db
        |> select_all(
          "SELECT id, query FROM pghero_queries WHERE query IN (#{placeholders})",
          queries,
          stats: true
        )
        |> Map.new(fn q -> {q[:query], q[:id]} end)
      end

    new_queries = Enum.reject(queries, &Map.has_key?(existing, &1))

    new_ids =
      Enum.reduce(new_queries, existing, fn query, acc ->
        rows =
          select_all(db, "INSERT INTO pghero_queries (query) VALUES ($1) RETURNING id", [query],
            stats: true
          )

        id = hd(rows)[:id]
        Map.put(acc, query, id)
      end)

    new_ids
  end

  defp optional_eq(clause, value, params, next \\ 1)

  defp optional_eq(_clause, nil, params, next), do: {"", params, next}

  defp optional_eq(clause, value, params, next) do
    {"#{clause} = $#{next}", params ++ [value], next + 1}
  end

  defp optional_cmp(_clause, nil, params, next), do: {"", params, next}

  defp optional_cmp(clause, value, params, next) do
    {"#{clause} $#{next}", params ++ [value], next + 1}
  end

  defp maybe_reject_min_average(stats, nil), do: stats

  defp maybe_reject_min_average(stats, min),
    do: Enum.reject(stats, fn q -> q[:average_time] < min end)

  defp maybe_reject_min_calls(stats, nil), do: stats
  defp maybe_reject_min_calls(stats, min), do: Enum.reject(stats, fn q -> q[:calls] < min end)

  defp first_present(stats, key) do
    stats |> Enum.map(& &1[key]) |> Enum.find(& &1)
  end

  defp to_dt(%DateTime{} = dt), do: dt
  defp to_dt(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp to_integer(n) when is_integer(n), do: n
  defp to_integer(n) when is_binary(n), do: String.to_integer(n)
end
