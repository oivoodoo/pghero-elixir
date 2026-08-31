defmodule PgHero.Methods.Connections do
  @moduledoc false

  import PgHero.Query

  def connections(db) do
    select_all(db, """
    SELECT
      pg_stat_activity.pid,
      datname AS database,
      usename AS user,
      application_name AS source,
      client_addr AS ip,
      state,
      ssl
    FROM
      pg_stat_activity
    LEFT JOIN
      pg_stat_ssl ON pg_stat_activity.pid = pg_stat_ssl.pid
    ORDER BY
      pg_stat_activity.pid
    """)
  end

  def total_connections(db) do
    select_one(db, "SELECT COUNT(*) FROM pg_stat_activity")
  end

  def connection_states(db) do
    db
    |> select_all("""
    SELECT
      state,
      COUNT(*) AS connections
    FROM
      pg_stat_activity
    GROUP BY
      1
    ORDER BY
      2 DESC, 1
    """)
    |> Map.new(fn s -> {s[:state], s[:connections]} end)
  end

  def connection_sources(db) do
    select_all(db, """
    SELECT
      datname AS database,
      usename AS user,
      application_name AS source,
      client_addr AS ip,
      COUNT(*) AS total_connections
    FROM
      pg_stat_activity
    GROUP BY
      1, 2, 3, 4
    ORDER BY
      5 DESC, 1, 2, 3, 4
    """)
  end
end
