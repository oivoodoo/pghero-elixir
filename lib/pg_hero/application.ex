defmodule PgHero.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    if standalone?() and map_size(PgHero.Config.get().databases) == 0 do
      IO.puts(:stderr, """
      PgHero needs a database URL.

      Set DATABASE_URL, for example:

        docker run -e DATABASE_URL=postgres://user:pass@hostname:5432/dbname -p 8080:8080 pghero
      """)

      System.halt(1)
    end

    children = PgHero.Config.connection_children() ++ PgHero.Standalone.children()
    opts = [strategy: :one_for_one, name: PgHero.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp standalone? do
    Application.get_env(:pghero, :standalone, false) == true or
      System.get_env("PGHERO_SERVER") in ["1", "true"]
  end
end
