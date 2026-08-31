defmodule PgHero.Methods.Basic do
  @moduledoc false

  import PgHero.Query

  def ssl_used?(db) do
    with_transaction(
      db,
      fn conn ->
        try do
          execute(%{db | conn: conn}, "CREATE EXTENSION IF NOT EXISTS sslinfo")
        rescue
          _ in Postgrex.Error -> :ok
        end

        select_one(%{db | conn: conn}, "SELECT ssl_is_used()")
      end,
      rollback: true
    )
  end

  def database_name(db), do: select_one(db, "SELECT current_database()")
  def current_user(db), do: select_one(db, "SELECT current_user")
  def server_version(db), do: select_one(db, "SHOW server_version")

  def server_version_num(db) do
    db
    |> select_one("SHOW server_version_num")
    |> to_string()
    |> String.to_integer()
  end

  def table_exists?(db, table, opts \\ []) do
    sql = """
    SELECT EXISTS (
      SELECT 1
      FROM information_schema.tables
      WHERE table_name = $1
    )
    """

    select_one(db, sql, [table], opts) == true
  end
end
