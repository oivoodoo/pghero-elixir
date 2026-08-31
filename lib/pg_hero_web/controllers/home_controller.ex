defmodule PgHeroWeb.HomeController do
  use PgHeroWeb, :controller

  alias PgHero.Database

  def index(conn, params) do
    database = conn.assigns.database
    replica? = conn.assigns.replica
    extended? = present?(params["extended"])

    {replication_lag, good_replication_lag, inactive_slots} =
      if replica? do
        lag = Database.replication_lag(database)
        {lag, is_nil(lag) or lag < 5, []}
      else
        slots = Enum.reject(Database.replication_slots(database), & &1[:active])
        {nil, true, slots}
      end

    long_running = Database.long_running_queries(database)
    {walsender, rest} = Enum.split_with(long_running, fn q -> q[:backend_type] == "walsender" end)

    {autovacuum, long_running} =
      Enum.split_with(rest, fn q -> String.starts_with?(to_string(q[:query]), "autovacuum:") end)

    connection_states = Database.connection_states(database)
    total_connections = connection_states |> Map.values() |> Enum.sum()
    idle_connections = connection_states["idle in transaction"] || 0

    {sequences, sequences_timeout} = rescue_timeout(fn -> Database.sequences(database) end, [])
    {readable, unreadable} = Enum.split_with(sequences, & &1[:readable])

    sequence_danger =
      Database.sequence_danger(database,
        threshold: float_param(params["sequence_threshold"], 0.9),
        sequences: readable
      )

    {indexes, indexes_timeout} =
      if sequences_timeout do
        {[], true}
      else
        rescue_timeout(fn -> Database.indexes(database) end, [])
      end

    {query_stats, slow_queries, query_stats_available, query_stats_extension_enabled} =
      if conn.assigns.query_stats_enabled do
        stats = Database.query_stats(database, historical: true, start_at: hours_ago(3))
        {stats, Database.slow_queries(database, query_stats: stats), nil, nil}
      else
        available = Database.query_stats_available?(database)
        enabled = if available, do: Database.query_stats_extension_enabled?(database), else: nil
        {[], [], available, enabled}
      end

    {index_hit_rate, table_hit_rate, unused_indexes, good_cache_rate} =
      if extended? do
        index_hit = Database.index_hit_rate(database) || 0
        table_hit = Database.table_hit_rate(database) || 0
        threshold = Database.cache_hit_rate_threshold(database) / 100.0

        unused =
          Database.unused_indexes(database,
            max_scans: 0,
            min_size: Database.unused_index_bytes(database)
          )

        {index_hit, table_hit, unused, table_hit >= threshold and index_hit >= threshold}
      else
        {nil, nil, [], true}
      end

    conn
    |> assign(:title, "Overview")
    |> assign(:extended, extended?)
    |> assign(:replication_lag, replication_lag)
    |> assign(:good_replication_lag, good_replication_lag)
    |> assign(:inactive_replication_slots, inactive_slots)
    |> assign(:walsender_queries, walsender)
    |> assign(:autovacuum_queries, autovacuum)
    |> assign(:long_running_queries, long_running)
    |> assign(:total_connections, total_connections)
    |> assign(:idle_connections, idle_connections)
    |> assign(
      :good_total_connections,
      total_connections < Database.total_connections_threshold(database)
    )
    |> assign(:good_idle_connections, idle_connections < 100)
    |> assign(
      :transaction_id_danger,
      Database.transaction_id_danger(database, threshold: 1_500_000_000)
    )
    |> assign(:sequences_timeout, sequences_timeout)
    |> assign(:readable_sequences, readable)
    |> assign(:unreadable_sequences, unreadable)
    |> assign(:sequence_danger, sequence_danger)
    |> assign(:indexes, indexes)
    |> assign(:indexes_timeout, indexes_timeout)
    |> assign(:invalid_indexes, Database.invalid_indexes(database, indexes: indexes))
    |> assign(:invalid_constraints, Database.invalid_constraints(database))
    |> assign(:duplicate_indexes, Database.duplicate_indexes(database, indexes: indexes))
    |> assign(:query_stats, query_stats)
    |> assign(:slow_queries, slow_queries)
    |> assign(:query_stats_available, query_stats_available)
    |> assign(:query_stats_extension_enabled, query_stats_extension_enabled)
    |> assign(:suggested_indexes, [])
    |> assign(:suggested_indexes_by_query, %{})
    |> assign(:index_hit_rate, index_hit_rate)
    |> assign(:table_hit_rate, table_hit_rate)
    |> assign(:unused_indexes, unused_indexes)
    |> assign(:good_cache_rate, good_cache_rate)
    |> render(:index)
  end

  def space(conn, params) do
    database = conn.assigns.database
    days = int_param(params["days"], 7)
    only_tables? = present?(params["tables"])

    {relation_sizes, sizes_timeout} =
      rescue_timeout(
        fn ->
          if only_tables?,
            do: Database.table_sizes(database),
            else: Database.relation_sizes(database)
        end,
        []
      )

    space_stats_enabled = Database.space_stats_enabled?(database) and not only_tables?

    {relation_sizes, growth} =
      if space_stats_enabled do
        growth = Database.space_growth(database, days: days, relation_sizes: relation_sizes)
        growth_map = Map.new(growth, fn r -> {{r[:schema], r[:relation]}, r[:growth_bytes]} end)

        sorted =
          case params["sort"] do
            "growth" ->
              Enum.sort_by(relation_sizes, fn r ->
                g = growth_map[{r[:schema], r[:relation]}]
                {if(g, do: 0, else: 1), -(g || 0), r[:schema], r[:relation]}
              end)

            "name" ->
              Enum.sort_by(relation_sizes, fn r -> r[:relation] || r[:table] end)

            _ ->
              relation_sizes
          end

        {sorted, growth_map}
      else
        sorted =
          if params["sort"] == "name" do
            Enum.sort_by(relation_sizes, fn r -> r[:relation] || r[:table] end)
          else
            relation_sizes
          end

        {sorted, %{}}
      end

    across = params["across"] |> to_string() |> String.split(",", trim: true)
    unused = Database.unused_indexes(database, max_scans: 0, across: across)
    unused_names = MapSet.new(unused, & &1[:index])

    unused =
      Enum.filter(unused, fn r -> r[:size_bytes] >= Database.unused_index_bytes(database) end)

    conn
    |> assign(:title, "Space")
    |> assign(:days, days)
    |> assign(:database_size, Database.database_size(database))
    |> assign(:only_tables, only_tables?)
    |> assign(:relation_sizes, relation_sizes)
    |> assign(:sizes_timeout, sizes_timeout)
    |> assign(:space_stats_enabled, space_stats_enabled)
    |> assign(:growth_bytes_by_relation, growth)
    |> assign(:header_options, if(only_tables?, do: %{"tables" => "t"}, else: %{}))
    |> assign(:unused_indexes, unused)
    |> assign(:unused_index_names, unused_names)
    |> render(:space)
  end

  def relation_space(conn, params) do
    database = conn.assigns.database
    schema = params["schema"] || "public"
    relation = params["relation"]
    stats = Database.relation_space_stats(database, relation, schema: schema)

    chart_data = [
      %{
        name: "Size",
        data: Enum.map(stats, fn r -> [js_time(r[:captured_at]), trunc(r[:size_bytes] || 0)] end)
      }
    ]

    conn
    |> assign(:title, relation)
    |> assign(:schema, schema)
    |> assign(:relation, relation)
    |> assign(:chart_data, chart_data)
    |> render(:relation_space)
  end

  def index_bloat(conn, params) do
    conn
    |> assign(:title, "Index Bloat")
    |> assign(:index_bloat, Database.index_bloat(conn.assigns.database))
    |> assign(:show_sql, present?(params["sql"]))
    |> render(:index_bloat)
  end

  def live_queries(conn, params) do
    queries = Database.running_queries(conn.assigns.database, all: true)
    vacuum = Map.new(Database.vacuum_progress(conn.assigns.database), fn q -> {q[:pid], q} end)

    queries =
      case params["state"] do
        nil -> queries
        state -> Enum.filter(queries, fn q -> q[:state] == state end)
      end

    conn
    |> assign(:title, "Live Queries")
    |> assign(:running_queries, queries)
    |> assign(:vacuum_progress, vacuum)
    |> render(:live_queries)
  end

  def queries(conn, params) do
    unless conn.assigns.query_stats_enabled do
      conn
      |> put_flash(:error, "Query stats not enabled")
      |> redirect(to: pg_path(conn, "/"))
    else
      database = conn.assigns.database
      sort = if params["sort"] in ["average_time", "calls"], do: params["sort"]
      min_average_time = maybe_int(params["min_average_time"])
      min_calls = maybe_int(params["min_calls"])
      user = params["user"]

      historical? =
        conn.assigns.query_stats_enabled and Database.historical_query_stats_enabled?(database)

      {start_at, end_at, error?} =
        if historical? do
          try do
            start_at = parse_time(params["start_at"]) || hours_ago(24)
            end_at = parse_time(params["end_at"])
            {start_at, end_at, false}
          rescue
            _ -> {nil, nil, true}
          end
        else
          {nil, nil, false}
        end

      query_stats =
        if historical? and not xhr?(conn) do
          []
        else
          Database.query_stats(database,
            historical: true,
            start_at: start_at,
            end_at: end_at,
            sort: sort,
            min_average_time: min_average_time,
            min_calls: min_calls
          )
        end

      query_stats =
        if user, do: Enum.filter(query_stats, fn v -> v[:user] == user end), else: query_stats

      conn =
        conn
        |> assign(:title, "Queries")
        |> assign(:sort, sort)
        |> assign(:min_average_time, min_average_time)
        |> assign(:min_calls, min_calls)
        |> assign(:user, user)
        |> assign(:link_user, is_nil(user))
        |> assign(:historical_query_stats_enabled, historical?)
        |> assign(:show_details, historical?)
        |> assign(:start_at, start_at)
        |> assign(:end_at, end_at)
        |> assign(:error, error?)
        |> assign(:query_stats, query_stats)
        |> assign(:suggested_indexes_by_query, %{})
        |> assign(:debug, present?(params["debug"]))
        |> assign(
          :link_options,
          maybe_put(%{sort: sort}, :start_at, params["start_at"])
          |> maybe_put(:end_at, params["end_at"])
        )
        |> put_resp_header("cache-control", "must-revalidate, no-store, no-cache, private")

      if xhr?(conn) do
        conn
        |> put_root_layout(false)
        |> put_layout(false)
        |> render(:queries_table, queries: query_stats, xhr: true, sort_headers: false)
      else
        render(conn, :queries)
      end
    end
  end

  def show_query(conn, params) do
    unless conn.assigns.query_stats_enabled do
      conn
      |> put_flash(:error, "Query stats not enabled")
      |> redirect(to: pg_path(conn, "/"))
    else
      query_hash = decode_query_hash(params["query_hash"] || "")
      database = conn.assigns.database
      historical? = Database.historical_query_stats_enabled?(database)

      stats =
        if query_hash do
          database
          |> Database.query_stats(
            historical: true,
            query_hash: query_hash,
            start_at: hours_ago(24)
          )
          |> List.first()
        end

      if stats do
        tables = []
        explainable = if Database.explainable?(database, stats[:query]), do: stats[:query]

        conn
        |> assign(:title, String.slice(stats[:query] || "", 0, 70))
        |> assign(:query, stats[:query])
        |> assign(:query_hash, query_hash)
        |> assign(:explainable_query, explainable)
        |> assign(:historical_query_stats_enabled, historical?)
        |> assign(:show_details, historical?)
        |> assign(:chart_data, nil)
        |> assign(:chart2_data, nil)
        |> assign(:chart3_data, nil)
        |> assign(:origins, %{})
        |> assign(:total_count, 0)
        |> assign(:tables, tables)
        |> assign(:row_counts, %{})
        |> assign(:indexes_by_table, %{})
        |> assign(:indexes_timeout, false)
        |> maybe_assign_details(database, query_hash, params["user"], historical?)
        |> render(:show_query)
      else
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Unknown query")
      end
    end
  end

  def explain(conn, params) do
    unless conn.assigns.explain_enabled do
      conn |> put_resp_content_type("text/plain") |> send_resp(400, "Explain not enabled")
    else
      query = params["query"]
      analyze_enabled? = PgHero.explain_analyze_enabled?()

      {explanation, suggested_index, visualize?, error} =
        if conn.method == "POST" and present?(query) do
          run_explain(
            conn.assigns.database,
            query,
            params["commit"] || params["explain"],
            analyze_enabled?
          )
        else
          {nil, nil, false, nil}
        end

      conn
      |> assign(:title, "Explain")
      |> assign(:query, query)
      |> assign(:explain_analyze_enabled, analyze_enabled?)
      |> assign(:explanation, explanation)
      |> assign(:suggested_index, suggested_index)
      |> assign(:visualize, visualize?)
      |> assign(:error, error)
      |> render(:explain)
    end
  end

  def tune(conn, params) do
    database = conn.assigns.database

    conn
    |> assign(:title, "Tune")
    |> assign(:settings, Database.settings(database))
    |> assign(
      :autovacuum_settings,
      if(present?(params["autovacuum"]), do: Database.autovacuum_settings(database))
    )
    |> render(:tune)
  end

  def connections(conn, params) do
    connections = Database.connections(conn.assigns.database)
    connections = if present?(params["security"]), do: tag_ssl(connections), else: connections

    conn
    |> assign(:title, "Connections")
    |> assign(:total_connections, length(connections))
    |> assign(
      :connection_sources,
      group_connections(connections, [:database, :user, :source, :ip])
    )
    |> assign(:connections_by_database, group_connections_by_key(connections, :database))
    |> assign(:connections_by_user, group_connections_by_key(connections, :user))
    |> assign(
      :connections_by_ssl_status,
      if(present?(params["security"]), do: group_connections_by_key(connections, :ssl_status))
    )
    |> render(:connections)
  end

  def maintenance(conn, params) do
    conn
    |> assign(:title, "Maintenance")
    |> assign(:maintenance_info, Database.maintenance_info(conn.assigns.database))
    |> assign(:show_dead_rows, present?(params["dead_rows"]))
    |> render(:maintenance)
  end

  def kill(conn, params) do
    ensure_kill!(conn)

    notice =
      if Database.kill(conn.assigns.database, params["pid"]) do
        "Query killed"
      else
        "Query no longer running"
      end

    redirect_back_notice(conn, notice)
  end

  def kill_long_running_queries(conn, _params) do
    ensure_kill!(conn)
    Database.kill_long_running_queries(conn.assigns.database)
    redirect_back_notice(conn, "Queries killed")
  end

  def kill_all(conn, _params) do
    ensure_kill!(conn)
    Database.kill_all(conn.assigns.database)
    redirect_back_notice(conn, "Connections killed")
  end

  def enable_query_stats(conn, _params) do
    Database.enable_query_stats(conn.assigns.database)
    redirect_back_notice(conn, "Query stats enabled")
  rescue
    _ in Postgrex.Error ->
      conn
      |> put_flash(:error, "The database user does not have permission to enable query stats")
      |> redirect(to: fallback(conn))
  end

  def reset_query_stats(conn, _params) do
    database = conn.assigns.database

    if Database.historical_query_stats_enabled?(database) or
         Database.query_stats_table_exists?(database) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(400, "Cannot reset when historical query stats are enabled")
    else
      if Database.reset_query_stats(database) do
        redirect_back_notice(conn, "Query stats reset")
      else
        conn
        |> put_flash(:error, "The database user does not have permission to reset query stats")
        |> redirect(to: fallback(conn))
      end
    end
  end

  defp maybe_assign_details(conn, database, query_hash, user, true) do
    stats = Database.query_hash_stats(database, query_hash, user: user)

    conn
    |> assign(:chart_data, [
      %{
        name: "Total Time",
        data: Enum.map(stats, fn r -> [js_time(r[:captured_at]), round(r[:total_time] || 0)] end)
      }
    ])
    |> assign(:chart2_data, [
      %{
        name: "Average Time",
        data:
          Enum.map(stats, fn r ->
            [js_time(r[:captured_at]), Float.round(r[:average_time] || 0, 1)]
          end)
      }
    ])
    |> assign(:chart3_data, [
      %{name: "Calls", data: Enum.map(stats, fn r -> [js_time(r[:captured_at]), r[:calls]] end)}
    ])
    |> assign(
      :origins,
      stats
      |> Enum.group_by(fn r -> to_string(r[:origin]) end)
      |> Map.new(fn {k, v} -> {k, length(v)} end)
    )
    |> assign(:total_count, length(stats))
  rescue
    _ -> conn
  end

  defp maybe_assign_details(conn, _database, _hash, _user, _), do: conn

  defp run_explain(database, query, commit, analyze_enabled?) do
    generic_plan =
      Database.server_version_num(database) >= 160_000 and String.contains?(query, "$1")

    {opts, visualize?} =
      case commit do
        "Analyze" ->
          {%{analyze: true}, false}

        "Visualize" ->
          if analyze_enabled? and not generic_plan do
            {%{analyze: true, costs: true, verbose: true, buffers: true, format: "json"}, true}
          else
            {%{costs: true, verbose: true, format: "json"}, true}
          end

        _ ->
          {%{}, false}
      end

    opts = if generic_plan, do: Map.put(opts, :generic_plan, true), else: opts

    if opts[:analyze] == true and not analyze_enabled? do
      {nil, nil, false, "Explain analyze not enabled"}
    else
      explanation = Database.explain(database, query, Enum.to_list(opts))
      {explanation, nil, visualize?, nil}
    end
  rescue
    e in Postgrex.Error ->
      message = Exception.message(e)

      error =
        cond do
          message == "Unsafe statement" or String.contains?(message, "Unsafe statement") ->
            "Unsafe statement"

          String.contains?(message, "undefined_parameter") or
              String.contains?(message, "UndefinedParameter") ->
            "Can't explain queries with bind parameters"

          String.contains?(message, "GENERIC_PLAN") ->
            "Can't analyze queries with bind parameters"

          String.contains?(message, "syntax error") or String.contains?(message, "SyntaxError") ->
            "Syntax error with query"

          String.contains?(message, "query_canceled") or
              String.contains?(message, "QueryCanceled") ->
            "Query timed out"

          true ->
            "Error explaining query"
        end

      {nil, nil, false, error}
  end

  defp tag_ssl(connections) do
    Enum.map(connections, fn connection ->
      ssl_status =
        cond do
          connection[:ssl] -> "SSL"
          not present?(connection[:database]) -> "Internal Process"
          is_nil(connection[:ip]) and connection[:state] -> "Socket"
          is_nil(connection[:ip]) -> "No SSL"
          true -> "No SSL"
        end

      Map.put(connection, :ssl_status, ssl_status)
    end)
  end

  defp group_connections(connections, keys) do
    connections
    |> Enum.group_by(fn conn -> Map.take(conn, keys) end)
    |> Enum.map(fn {k, v} -> Map.put(k, :total_connections, length(v)) end)
    |> Enum.sort_by(fn v ->
      [-v[:total_connections] | Enum.map(keys, fn k -> stringify(v[k]) end)]
    end)
  end

  defp group_connections_by_key(connections, key) do
    connections
    |> group_connections([key])
    |> Map.new(fn v -> {v[key], v[:total_connections]} end)
  end

  defp ensure_kill!(conn) do
    if conn.assigns.kill_enabled do
      conn
    else
      raise PgHero.Error, message: "Kill not enabled"
    end
  end

  defp redirect_back_notice(conn, notice) do
    conn
    |> put_flash(:info, notice)
    |> redirect(to: fallback(conn))
  end

  defp fallback(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)

        if uri.path,
          do: uri.path <> if(uri.query, do: "?" <> uri.query, else: ""),
          else: pg_path(conn, "/")

      _ ->
        pg_path(conn, "/")
    end
  end

  defp rescue_timeout(fun, default) do
    {fun.(), false}
  rescue
    e ->
      if PgHero.Query.timeout_error?(e), do: {default, true}, else: reraise(e, __STACKTRACE__)
  end

  defp stringify(nil), do: ""
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp stringify(value), do: inspect(value)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp int_param(nil, default), do: default
  defp int_param("", default), do: default
  defp int_param(value, _default), do: String.to_integer(value)

  defp maybe_int(nil), do: nil
  defp maybe_int(""), do: nil
  defp maybe_int(value), do: String.to_integer(value)

  defp float_param(nil, default), do: default
  defp float_param("", default), do: default

  defp float_param(value, _default) do
    case Float.parse(to_string(value)) do
      {n, _} -> n
      :error -> 0.9
    end
  end

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

  defp parse_time(nil), do: nil
  defp parse_time(""), do: nil

  defp parse_time(value) do
    cond do
      match = Regex.run(~r/\A(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})Z\z/, value) ->
        {:ok, dt, _} = DateTime.from_iso8601(Enum.at(match, 1) <> "Z")
        dt

      true ->
        {:ok, dt, _} = DateTime.from_iso8601(value)
        dt
    end
  end

  defp js_time(nil), do: nil
  defp js_time(%DateTime{} = dt), do: DateTime.to_unix(dt, :millisecond)

  defp js_time(%NaiveDateTime{} = dt),
    do: dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
