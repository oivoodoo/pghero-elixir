defmodule Mix.Tasks.Pghero.Server do
  @moduledoc """
  Starts a standalone PgHero dashboard.

      DATABASE_URL=postgres://user:pass@localhost/dbname mix pghero.server

  Options:

      --port 8080
  """
  use Mix.Task

  @shortdoc "Start a standalone PgHero HTTP server"

  @impl true
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [port: :integer])

    if port = opts[:port] do
      System.put_env("PORT", Integer.to_string(port))
    end

    System.put_env("PGHERO_SERVER", "true")
    PgHero.Standalone.configure!()

    Mix.Task.run("app.start")
    Mix.Tasks.Run.run(["--no-halt"])
  end
end
