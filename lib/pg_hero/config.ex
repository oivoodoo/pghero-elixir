defmodule PgHero.Config do
  @moduledoc false

  @env_keys %{
    long_running_query_sec: "PGHERO_LONG_RUNNING_QUERY_SEC",
    slow_query_ms: "PGHERO_SLOW_QUERY_MS",
    slow_query_calls: "PGHERO_SLOW_QUERY_CALLS",
    explain_timeout_sec: "PGHERO_EXPLAIN_TIMEOUT_SEC",
    total_connections_threshold: "PGHERO_TOTAL_CONNECTIONS_THRESHOLD",
    username: "PGHERO_USERNAME",
    password: "PGHERO_PASSWORD",
    stats_database_url: "PGHERO_STATS_DATABASE_URL",
    visualize_url: "PGHERO_VISUALIZE_URL"
  }

  def get do
    app = Application.get_all_env(:pghero) |> Map.new()

    %{
      long_running_query_sec:
        int(app, :long_running_query_sec, env_int("PGHERO_LONG_RUNNING_QUERY_SEC", 60)),
      slow_query_ms: int(app, :slow_query_ms, env_int("PGHERO_SLOW_QUERY_MS", 20)),
      slow_query_calls: int(app, :slow_query_calls, env_int("PGHERO_SLOW_QUERY_CALLS", 100)),
      explain_timeout_sec:
        float(app, :explain_timeout_sec, env_float("PGHERO_EXPLAIN_TIMEOUT_SEC", 10.0)),
      total_connections_threshold:
        int(app, :total_connections_threshold, env_int("PGHERO_TOTAL_CONNECTIONS_THRESHOLD", 500)),
      cache_hit_rate_threshold: int(app, :cache_hit_rate_threshold, 99),
      unused_index_megabytes: int(app, :unused_index_megabytes, 10),
      index_bloat_bytes: int(app, :index_bloat_bytes, 100 * 1024 * 1024),
      username: str(app, :username, System.get_env("PGHERO_USERNAME")),
      password: str(app, :password, System.get_env("PGHERO_PASSWORD")),
      stats_database_url:
        str(app, :stats_database_url, System.get_env("PGHERO_STATS_DATABASE_URL")),
      visualize_url:
        str(
          app,
          :visualize_url,
          System.get_env("PGHERO_VISUALIZE_URL") || "https://tatiyants.com/pev/#/plans/new"
        ),
      explain: Map.get(app, :explain, true),
      disable_kill: Map.get(app, :disable_kill, false),
      override_csp: Map.get(app, :override_csp, true),
      show_migrations: Map.get(app, :show_migrations, true),
      filter_data: Map.get(app, :filter_data, present?(System.get_env("PGHERO_FILTER_DATA"))),
      databases: databases(app)
    }
  end

  def connection_children do
    get().databases
    |> Enum.flat_map(fn {_id, cfg} ->
      case cfg[:url] do
        url when is_binary(url) and url != "" ->
          name = connection_name(cfg[:id])

          [
            %{
              id: name,
              start: {Postgrex, :start_link, [Keyword.merge(postgrex_opts(url), name: name)]}
            }
          ]

        _ ->
          []
      end
    end)
    |> maybe_stats_child()
  end

  def connection_name(id), do: Module.concat(PgHero.Connections, Macro.camelize(to_string(id)))

  def stats_connection_name, do: PgHero.Connections.Stats

  defp maybe_stats_child(children) do
    case get().stats_database_url do
      url when is_binary(url) and url != "" ->
        child = %{
          id: stats_connection_name(),
          start:
            {Postgrex, :start_link,
             [Keyword.merge(postgrex_opts(url), name: stats_connection_name())]}
        }

        [child | children]

      _ ->
        children
    end
  end

  defp databases(app) do
    cond do
      is_list(app[:databases]) ->
        app[:databases]
        |> Enum.map(&normalize_database/1)
        |> Map.new(fn db -> {db[:id], db} end)

      is_map(app[:databases]) ->
        Map.new(app[:databases], fn {id, cfg} ->
          db = normalize_database({id, cfg})
          {db[:id], db}
        end)

      repo = app[:repo] ->
        %{primary: normalize_database({:primary, [repo: repo]})}

      url = app[:url] || System.get_env("PGHERO_DATABASE_URL") ->
        %{primary: normalize_database({:primary, [url: url]})}

      true ->
        %{}
    end
  end

  defp normalize_database({id, cfg}) when is_list(cfg) do
    Keyword.merge(cfg, id: to_string(id), name: cfg[:name] || titleize(id))
  end

  defp normalize_database({id, cfg}) when is_map(cfg) do
    normalize_database({id, Map.to_list(cfg)})
  end

  defp titleize(id) do
    id
    |> to_string()
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp postgrex_opts(url) do
    uri = URI.parse(url)
    {user, password} = userinfo(uri)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: password,
      database: database_name(uri.path),
      timeout: 30_000,
      handshake_timeout: 5_000,
      pool_size: 2,
      backoff_type: :stop
    ]
    |> maybe_ssl(uri)
  end

  defp maybe_ssl(opts, %URI{scheme: "postgres"}), do: opts
  defp maybe_ssl(opts, %URI{scheme: "postgresql"}), do: opts

  defp maybe_ssl(opts, %URI{query: query}) when is_binary(query) do
    params = URI.decode_query(query)

    if params["sslmode"] in ["require", "verify-full", "verify-ca"] do
      Keyword.put(opts, :ssl, true)
    else
      opts
    end
  end

  defp maybe_ssl(opts, _), do: opts

  defp userinfo(%URI{userinfo: nil}), do: {nil, nil}

  defp userinfo(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {URI.decode(user), nil}
      [user, password] -> {URI.decode(user), URI.decode(password)}
    end
  end

  defp database_name(nil), do: "postgres"
  defp database_name("/"), do: "postgres"
  defp database_name("/" <> name), do: URI.decode(name)
  defp database_name(name), do: name

  defp int(app, key, default) do
    case Map.get(app, key, default) do
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> default
    end
  end

  defp float(app, key, default) do
    case Map.get(app, key, default) do
      n when is_number(n) -> n * 1.0
      n when is_binary(n) -> String.to_float(n)
      _ -> default
    end
  end

  defp str(app, key, default) do
    case Map.get(app, key, default) do
      n when is_binary(n) and n != "" -> n
      _ -> default
    end
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end

  defp env_float(key, default) do
    case System.get_env(key) do
      nil ->
        default

      "" ->
        default

      value ->
        case Float.parse(value) do
          {n, _} -> n
          :error -> default
        end
    end
  end

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  def env_keys, do: @env_keys
end
