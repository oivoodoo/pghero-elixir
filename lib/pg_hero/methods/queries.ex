defmodule PgHero.Methods.Queries do
  @moduledoc false

  import PgHero.Query

  def running_queries(db, opts \\ []) do
    min_duration = opts[:min_duration]
    all? = Keyword.get(opts, :all, false)

    {duration_sql, params} =
      if min_duration do
        {"AND NOW() - COALESCE(query_start, xact_start) > interval '1 second' * $1",
         [min_duration]}
      else
        {"", []}
      end

    privilege_sql = if all?, do: "", else: "AND query <> '<insufficient privilege>'"

    sql = """
    SELECT
      pid,
      state,
      application_name AS source,
      age(NOW(), COALESCE(query_start, xact_start)) AS duration,
      wait_event IS NOT NULL AS waiting,
      query,
      COALESCE(query_start, xact_start) AS started_at,
      EXTRACT(EPOCH FROM NOW() - COALESCE(query_start, xact_start)) * 1000.0 AS duration_ms,
      usename AS user,
      backend_type
    FROM
      pg_stat_activity
    WHERE
      state <> 'idle'
      AND pid <> pg_backend_pid()
      AND datname = current_database()
      #{duration_sql}
      #{privilege_sql}
    ORDER BY
      COALESCE(query_start, xact_start) DESC
    """

    select_all(db, sql, params)
  end

  def long_running_queries(db) do
    running_queries(db, min_duration: PgHero.Database.long_running_query_sec(db))
  end

  def blocked_queries(db) do
    select_all(db, """
    SELECT
      COALESCE(blockingl.relation::regclass::text,blockingl.locktype) as locked_item,
      blockeda.pid AS blocked_pid,
      blockeda.usename AS blocked_user,
      blockeda.query as blocked_query,
      age(now(), blockeda.query_start) AS blocked_duration,
      blockedl.mode as blocked_mode,
      blockinga.pid AS blocking_pid,
      blockinga.usename AS blocking_user,
      blockinga.state AS state_of_blocking_process,
      blockinga.query AS current_or_recent_query_in_blocking_process,
      age(now(), blockinga.query_start) AS blocking_duration,
      blockingl.mode as blocking_mode
    FROM
      pg_catalog.pg_locks blockedl
    LEFT JOIN
      pg_stat_activity blockeda ON blockedl.pid = blockeda.pid
    LEFT JOIN
      pg_catalog.pg_locks blockingl ON blockedl.pid != blockingl.pid AND (
        blockingl.transactionid = blockedl.transactionid
        OR (blockingl.relation = blockedl.relation AND blockingl.locktype = blockedl.locktype)
      )
    LEFT JOIN
      pg_stat_activity blockinga ON blockingl.pid = blockinga.pid AND blockinga.datid = blockeda.datid
    WHERE
      NOT blockedl.granted
      AND blockeda.query <> '<insufficient privilege>'
      AND blockeda.datname = current_database()
    ORDER BY
      blocked_duration DESC
    """)
  end
end
