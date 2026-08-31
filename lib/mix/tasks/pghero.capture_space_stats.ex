defmodule Mix.Tasks.Pghero.CaptureSpaceStats do
  @moduledoc """
  Captures relation sizes for historical space tracking.

      mix pghero.capture_space_stats
  """
  use Mix.Task

  @shortdoc "Capture PgHero space stats"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    PgHero.capture_space_stats(verbose: true)
  end
end
