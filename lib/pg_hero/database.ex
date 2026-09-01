defmodule PgHero.Database do
  @moduledoc """
  A configured Postgres database and the query helpers used by the dashboard.
  """

  defstruct [:id, :name, :config, :conn]

  alias PgHero.Methods.{
    Basic,
    Connections,
    Constraints,
    Explain,
    Indexes,
    Kill,
    Maintenance,
    Queries,
    QueryStats,
    Replication,
    Sequences,
    Settings,
    Space,
    Tables
  }

  def build(id, config) do
    id = to_string(id)
    config = Map.new(config)

    %__MODULE__{
      id: id,
      name: config[:name] || titleize(id),
      config: config,
      conn: build_conn(id, config)
    }
  end

  def capture_query_stats?(%__MODULE__{config: config}) do
    Map.get(config, :capture_query_stats, true) != false
  end

  def cache_hit_rate_threshold(db), do: int_setting(db, :cache_hit_rate_threshold)
  def total_connections_threshold(db), do: int_setting(db, :total_connections_threshold)
  def slow_query_ms(db), do: int_setting(db, :slow_query_ms)
  def slow_query_calls(db), do: int_setting(db, :slow_query_calls)
  def explain_timeout_sec(db), do: float_setting(db, :explain_timeout_sec)
  def long_running_query_sec(db), do: int_setting(db, :long_running_query_sec)

  def unused_index_bytes(db) do
    megabytes =
      db.config[:unused_index_megabytes] ||
        PgHero.config().unused_index_megabytes

    trunc(megabytes * 1024 * 1024)
  end

  def index_bloat_bytes(db) do
    db.config[:index_bloat_bytes] || PgHero.config().index_bloat_bytes
  end

  # Wrappers instead of defdelegate so ExDoc does not emit "See
  # PgHero.Methods.* which is hidden" warnings for the internal method modules.
  def ssl_used?(db), do: Basic.ssl_used?(db)
  def database_name(db), do: Basic.database_name(db)
  def current_user(db), do: Basic.current_user(db)
  def server_version(db), do: Basic.server_version(db)
  def server_version_num(db), do: Basic.server_version_num(db)

  def connections(db), do: Connections.connections(db)
  def total_connections(db), do: Connections.total_connections(db)
  def connection_states(db), do: Connections.connection_states(db)
  def connection_sources(db), do: Connections.connection_sources(db)

  def invalid_constraints(db), do: Constraints.invalid_constraints(db)

  def explain(db, sql, opts \\ []), do: Explain.explain(db, sql, opts)

  def index_hit_rate(db), do: Indexes.index_hit_rate(db)
  def index_caching(db), do: Indexes.index_caching(db)
  def index_usage(db), do: Indexes.index_usage(db)
  def missing_indexes(db), do: Indexes.missing_indexes(db)
  def unused_indexes(db, opts \\ []), do: Indexes.unused_indexes(db, opts)
  def reset_stats(db), do: Indexes.reset_stats(db)
  def last_stats_reset_time(db), do: Indexes.last_stats_reset_time(db)
  def invalid_indexes(db, opts \\ []), do: Indexes.invalid_indexes(db, opts)
  def indexes(db), do: Indexes.indexes(db)
  def duplicate_indexes(db, opts \\ []), do: Indexes.duplicate_indexes(db, opts)
  def index_bloat(db, opts \\ []), do: Indexes.index_bloat(db, opts)

  def kill(db, pid), do: Kill.kill(db, pid)
  def kill_long_running_queries(db, opts \\ []), do: Kill.kill_long_running_queries(db, opts)
  def kill_all(db), do: Kill.kill_all(db)

  def transaction_id_danger(db, opts \\ []), do: Maintenance.transaction_id_danger(db, opts)
  def autovacuum_danger(db), do: Maintenance.autovacuum_danger(db)
  def vacuum_progress(db), do: Maintenance.vacuum_progress(db)
  def maintenance_info(db), do: Maintenance.maintenance_info(db)
  def analyze(db, table, opts \\ []), do: Maintenance.analyze(db, table, opts)
  def analyze_tables(db, opts \\ []), do: Maintenance.analyze_tables(db, opts)

  def running_queries(db, opts \\ []), do: Queries.running_queries(db, opts)
  def long_running_queries(db), do: Queries.long_running_queries(db)
  def blocked_queries(db), do: Queries.blocked_queries(db)

  def query_stats(db, opts \\ []), do: QueryStats.query_stats(db, opts)
  def query_stats_available?(db), do: QueryStats.query_stats_available?(db)
  def query_stats_enabled?(db), do: QueryStats.query_stats_enabled?(db)
  def query_stats_extension_enabled?(db), do: QueryStats.query_stats_extension_enabled?(db)
  def query_stats_readable?(db), do: QueryStats.query_stats_readable?(db)
  def enable_query_stats(db), do: QueryStats.enable_query_stats(db)
  def disable_query_stats(db), do: QueryStats.disable_query_stats(db)
  def reset_query_stats(db, opts \\ []), do: QueryStats.reset_query_stats(db, opts)
  def historical_query_stats_enabled?(db), do: QueryStats.historical_query_stats_enabled?(db)
  def queries_table_exists?(db), do: QueryStats.queries_table_exists?(db)
  def query_stats_table_exists?(db), do: QueryStats.query_stats_table_exists?(db)
  def capture_query_stats(db, opts \\ []), do: QueryStats.capture_query_stats(db, opts)
  def clean_query_stats(db, opts \\ []), do: QueryStats.clean_query_stats(db, opts)
  def slow_queries(db, opts \\ []), do: QueryStats.slow_queries(db, opts)

  def query_hash_stats(db, query_hash, opts \\ []),
    do: QueryStats.query_hash_stats(db, query_hash, opts)

  def explainable?(db, query), do: QueryStats.explainable?(db, query)

  def replica?(db), do: Replication.replica?(db)
  def replication_lag(db), do: Replication.replication_lag(db)
  def replication_slots(db), do: Replication.replication_slots(db)
  def replicating?(db), do: Replication.replicating?(db)

  def sequences(db), do: Sequences.sequences(db)
  def sequence_danger(db, opts \\ []), do: Sequences.sequence_danger(db, opts)

  def settings(db), do: Settings.settings(db)
  def autovacuum_settings(db), do: Settings.autovacuum_settings(db)
  def vacuum_settings(db), do: Settings.vacuum_settings(db)

  def database_size(db), do: Space.database_size(db)
  def relation_sizes(db), do: Space.relation_sizes(db)
  def table_sizes(db), do: Space.table_sizes(db)
  def space_growth(db, opts \\ []), do: Space.space_growth(db, opts)

  def relation_space_stats(db, relation, opts \\ []),
    do: Space.relation_space_stats(db, relation, opts)

  def capture_space_stats(db), do: Space.capture_space_stats(db)
  def clean_space_stats(db, opts \\ []), do: Space.clean_space_stats(db, opts)
  def space_stats_enabled?(db), do: Space.space_stats_enabled?(db)

  def table_hit_rate(db), do: Tables.table_hit_rate(db)
  def table_caching(db), do: Tables.table_caching(db)
  def unused_tables(db), do: Tables.unused_tables(db)
  def table_stats(db, opts \\ []), do: Tables.table_stats(db, opts)

  def suggested_indexes_enabled?(_db), do: false
  def suggested_indexes(_db, _opts \\ []), do: []
  def suggested_indexes_by_query(_db, _opts \\ []), do: %{}
  def system_stats_enabled?(_db), do: false
  def system_stats_provider(_db), do: nil

  defp build_conn(id, config) do
    cond do
      repo = config[:repo] ->
        {:repo, repo}

      is_binary(config[:url]) and config[:url] != "" ->
        {:pid, PgHero.Config.connection_name(id)}

      true ->
        raise PgHero.Error, message: "Database #{id} needs :repo or :url"
    end
  end

  defp int_setting(db, key) do
    db.config[key] || Map.fetch!(PgHero.config(), key)
  end

  defp float_setting(db, key) do
    (db.config[key] || Map.fetch!(PgHero.config(), key)) * 1.0
  end

  defp titleize(id) do
    id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
