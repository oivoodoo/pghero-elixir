defmodule PgHero.Migrations do
  @moduledoc """
  Ecto migrations for historical query and space stats.

      defmodule MyApp.Repo.Migrations.CreatePgheroStats do
        use Ecto.Migration

        def up, do: PgHero.Migrations.up()
        def down, do: PgHero.Migrations.down()
      end
  """

  def up do
    repo = ecto_migration_repo()

    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS pghero_queries (
      id bigserial PRIMARY KEY,
      query text
    )
    """)

    Ecto.Migration.execute(
      "CREATE INDEX IF NOT EXISTS pghero_queries_query_idx ON pghero_queries USING hash (query)"
    )

    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS pghero_query_stats (
      id bigserial PRIMARY KEY,
      database text,
      "user" text,
      query_id bigint,
      query_hash bigint,
      total_time float,
      calls bigint,
      captured_at timestamp
    )
    """)

    Ecto.Migration.execute(
      "CREATE INDEX IF NOT EXISTS pghero_query_stats_database_captured_at_idx ON pghero_query_stats (database, captured_at)"
    )

    Ecto.Migration.execute("""
    CREATE TABLE IF NOT EXISTS pghero_space_stats (
      id bigserial PRIMARY KEY,
      database text,
      schema text,
      relation text,
      size bigint,
      captured_at timestamp
    )
    """)

    Ecto.Migration.execute(
      "CREATE INDEX IF NOT EXISTS pghero_space_stats_database_captured_at_idx ON pghero_space_stats (database, captured_at)"
    )

    repo
  end

  def down do
    Ecto.Migration.execute("DROP TABLE IF EXISTS pghero_space_stats")
    Ecto.Migration.execute("DROP TABLE IF EXISTS pghero_query_stats")
    Ecto.Migration.execute("DROP TABLE IF EXISTS pghero_queries")
  end

  defp ecto_migration_repo, do: :ok
end
