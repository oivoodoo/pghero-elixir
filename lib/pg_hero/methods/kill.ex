defmodule PgHero.Methods.Kill do
  @moduledoc false

  import PgHero.Query

  def kill(db, pid) do
    select_one(db, "SELECT pg_terminate_backend($1)", [to_pid(pid)])
  end

  def kill_long_running_queries(db, opts \\ []) do
    min_duration = opts[:min_duration] || PgHero.Database.long_running_query_sec(db)

    db
    |> PgHero.Methods.Queries.running_queries(min_duration: min_duration)
    |> Enum.each(fn query -> kill(db, query[:pid]) end)

    true
  end

  def kill_all(db) do
    select_all(db, """
    SELECT
      pg_terminate_backend(pid)
    FROM
      pg_stat_activity
    WHERE
      pid <> pg_backend_pid()
      AND query <> '<insufficient privilege>'
      AND datname = current_database()
    """)

    true
  end

  defp to_pid(pid) when is_integer(pid), do: pid
  defp to_pid(pid) when is_binary(pid), do: String.to_integer(pid)
end
