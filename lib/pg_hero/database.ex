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

  defdelegate ssl_used?(db), to: Basic
  defdelegate database_name(db), to: Basic
  defdelegate current_user(db), to: Basic
  defdelegate server_version(db), to: Basic
  defdelegate server_version_num(db), to: Basic

  defdelegate connections(db), to: Connections
  defdelegate total_connections(db), to: Connections
  defdelegate connection_states(db), to: Connections
  defdelegate connection_sources(db), to: Connections

  defdelegate invalid_constraints(db), to: Constraints

  defdelegate explain(db, sql, opts \\ []), to: Explain

  defdelegate index_hit_rate(db), to: Indexes
  defdelegate index_caching(db), to: Indexes
  defdelegate index_usage(db), to: Indexes
  defdelegate missing_indexes(db), to: Indexes
  defdelegate unused_indexes(db, opts \\ []), to: Indexes
  defdelegate reset_stats(db), to: Indexes
  defdelegate last_stats_reset_time(db), to: Indexes
  defdelegate invalid_indexes(db, opts \\ []), to: Indexes
  defdelegate indexes(db), to: Indexes
  defdelegate duplicate_indexes(db, opts \\ []), to: Indexes
  defdelegate index_bloat(db, opts \\ []), to: Indexes

  defdelegate kill(db, pid), to: Kill
  defdelegate kill_long_running_queries(db, opts \\ []), to: Kill
  defdelegate kill_all(db), to: Kill

  defdelegate transaction_id_danger(db, opts \\ []), to: Maintenance
  defdelegate autovacuum_danger(db), to: Maintenance
  defdelegate vacuum_progress(db), to: Maintenance
  defdelegate maintenance_info(db), to: Maintenance
  defdelegate analyze(db, table, opts \\ []), to: Maintenance
  defdelegate analyze_tables(db, opts \\ []), to: Maintenance

  defdelegate running_queries(db, opts \\ []), to: Queries
  defdelegate long_running_queries(db), to: Queries
  defdelegate blocked_queries(db), to: Queries

  defdelegate query_stats(db, opts \\ []), to: QueryStats
  defdelegate query_stats_available?(db), to: QueryStats
  defdelegate query_stats_enabled?(db), to: QueryStats
  defdelegate query_stats_extension_enabled?(db), to: QueryStats
  defdelegate query_stats_readable?(db), to: QueryStats
  defdelegate enable_query_stats(db), to: QueryStats
  defdelegate disable_query_stats(db), to: QueryStats
  defdelegate reset_query_stats(db, opts \\ []), to: QueryStats
  defdelegate historical_query_stats_enabled?(db), to: QueryStats
  defdelegate queries_table_exists?(db), to: QueryStats
  defdelegate query_stats_table_exists?(db), to: QueryStats
  defdelegate capture_query_stats(db, opts \\ []), to: QueryStats
  defdelegate clean_query_stats(db, opts \\ []), to: QueryStats
  defdelegate slow_queries(db, opts \\ []), to: QueryStats
  defdelegate query_hash_stats(db, query_hash, opts \\ []), to: QueryStats
  defdelegate explainable?(db, query), to: QueryStats

  defdelegate replica?(db), to: Replication
  defdelegate replication_lag(db), to: Replication
  defdelegate replication_slots(db), to: Replication
  defdelegate replicating?(db), to: Replication

  defdelegate sequences(db), to: Sequences
  defdelegate sequence_danger(db, opts \\ []), to: Sequences

  defdelegate settings(db), to: Settings
  defdelegate autovacuum_settings(db), to: Settings
  defdelegate vacuum_settings(db), to: Settings

  defdelegate database_size(db), to: Space
  defdelegate relation_sizes(db), to: Space
  defdelegate table_sizes(db), to: Space
  defdelegate space_growth(db, opts \\ []), to: Space
  defdelegate relation_space_stats(db, relation, opts \\ []), to: Space
  defdelegate capture_space_stats(db), to: Space
  defdelegate clean_space_stats(db, opts \\ []), to: Space
  defdelegate space_stats_enabled?(db), to: Space

  defdelegate table_hit_rate(db), to: Tables
  defdelegate table_caching(db), to: Tables
  defdelegate unused_tables(db), to: Tables
  defdelegate table_stats(db, opts \\ []), to: Tables

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
