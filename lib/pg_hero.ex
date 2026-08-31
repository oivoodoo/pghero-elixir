defmodule PgHero do
  @moduledoc """
  A performance dashboard for Postgres, mountable in Phoenix.

  Add it to your router:

      import PgHeroWeb.Router

      scope "/" do
        pipe_through [:browser, :require_admin]
        pghero "/pghero"
      end

  And configure a database:

      config :pghero, repo: MyApp.Repo
  """

  alias PgHero.{Config, Database}

  def config, do: Config.get()

  def databases do
    config().databases
    |> Enum.map(fn {id, cfg} -> {to_string(id), Database.build(id, cfg)} end)
    |> Map.new()
  end

  def database(id) when is_atom(id), do: database(Atom.to_string(id))

  def database(id) when is_binary(id) do
    Map.get(databases(), id)
  end

  def capture_query_stats(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    each_database(fn database ->
      if Database.capture_query_stats?(database) do
        if verbose?, do: IO.puts("Capturing query stats for #{database.id}...")
        Database.capture_query_stats(database, raise_errors: true)
      end
    end)
  end

  def capture_space_stats(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)

    each_database(fn database ->
      if verbose?, do: IO.puts("Capturing space stats for #{database.id}...")
      Database.capture_space_stats(database)
    end)
  end

  def analyze_all(opts \\ []) do
    each_database(fn database ->
      unless Database.replica?(database) do
        Database.analyze_tables(database, opts)
      end
    end)
  end

  def clean_query_stats(opts \\ []) do
    before = Keyword.get(opts, :before)

    each_database(fn database ->
      Database.clean_query_stats(database, before: before)
    end)
  end

  def clean_space_stats(opts \\ []) do
    before = Keyword.get(opts, :before)

    each_database(fn database ->
      Database.clean_space_stats(database, before: before)
    end)
  end

  def pretty_size(value), do: PgHero.Pretty.size(value)

  def explain_enabled? do
    mode = config().explain
    mode == nil or mode == true or mode == "analyze"
  end

  def explain_analyze_enabled? do
    config().explain == "analyze"
  end

  def kill_enabled? do
    not config().disable_kill
  end

  defp each_database(fun) do
    first_error =
      Enum.reduce(databases(), nil, fn {_id, database}, acc ->
        try do
          fun.(database)
          acc
        rescue
          e ->
            IO.puts("#{e.__struct__}: #{Exception.message(e)}")
            IO.puts("")
            acc || e
        end
      end)

    if first_error, do: raise(first_error)
    true
  end
end
