defmodule Mix.Tasks.Pghero.CaptureQueryStats do
  @moduledoc """
  Captures query stats for historical tracking.

      mix pghero.capture_query_stats
  """
  use Mix.Task

  @shortdoc "Capture PgHero query stats"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    PgHero.capture_query_stats(verbose: true)
  end
end
