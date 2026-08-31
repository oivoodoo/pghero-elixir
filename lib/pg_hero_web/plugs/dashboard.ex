defmodule PgHeroWeb.Plugs.Dashboard do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    mount_path = normalize_path(opts[:mount_path] || "/pghero")

    conn
    |> assign(:pghero_prefix, mount_path)
    |> maybe_basic_auth(opts)
    |> maybe_override_csp()
    |> assign_databases()
    |> assign_current_database()
    |> maybe_halt()
    |> maybe_redirect_multi_db()
    |> check_server_version()
    |> assign_flags()
  end

  defp maybe_basic_auth(conn, opts) do
    username = opts[:username] || PgHero.config().username
    password = opts[:password] || PgHero.config().password

    if is_binary(password) and password != "" do
      Plug.BasicAuth.basic_auth(conn, username: username || "", password: password)
    else
      conn
    end
  end

  defp maybe_override_csp(conn) do
    if PgHero.config().override_csp do
      put_resp_header(
        conn,
        "content-security-policy",
        "default-src 'self' 'unsafe-inline' 'unsafe-eval'"
      )
    else
      conn
    end
  end

  defp assign_databases(conn) do
    databases = PgHero.databases() |> Map.values() |> Enum.sort_by(& &1.id)
    assign(conn, :databases, databases)
  end

  defp assign_current_database(%{halted: true} = conn), do: conn

  defp assign_current_database(conn) do
    databases = conn.assigns.databases
    param = conn.params["database"]

    database =
      cond do
        is_binary(param) ->
          Enum.find(databases, fn d -> d.id == param end)

        length(databases) == 1 ->
          List.first(databases)

        true ->
          nil
      end

    conn
    |> assign(:database, database)
    |> assign(:pghero_database_in_path, length(databases) > 1 and not is_nil(database))
  end

  defp maybe_halt(%{halted: true} = conn), do: conn

  defp maybe_halt(%{assigns: %{databases: []}} = conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(500, "PgHero is not configured. Set config :pghero, repo: MyApp.Repo")
    |> halt()
  end

  defp maybe_halt(%{assigns: %{database: nil}, params: %{"database" => _}} = conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(404, "Unknown database")
    |> halt()
  end

  defp maybe_halt(conn), do: conn

  defp maybe_redirect_multi_db(%{halted: true} = conn), do: conn

  defp maybe_redirect_multi_db(%{assigns: %{database: nil, databases: [first | _]}} = conn) do
    prefix = conn.assigns.pghero_prefix
    rest = conn.path_info |> extra_path(conn.assigns.pghero_prefix) |> Enum.join("/")
    target = Path.join([prefix, first.id, rest]) |> String.replace(~r{/+}, "/")
    target = if conn.query_string == "", do: target, else: target <> "?" <> conn.query_string

    conn
    |> Phoenix.Controller.redirect(to: target)
    |> halt()
  end

  defp maybe_redirect_multi_db(conn), do: conn

  defp check_server_version(%{halted: true} = conn), do: conn
  defp check_server_version(%{assigns: %{database: nil}} = conn), do: conn

  defp check_server_version(conn) do
    version = PgHero.Database.server_version_num(conn.assigns.database)

    if version < 140_000 do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(500, "Requires PostgreSQL 14+")
      |> halt()
    else
      conn
    end
  rescue
    e ->
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(500, "Could not connect to Postgres: #{Exception.message(e)}")
      |> halt()
  end

  defp assign_flags(%{halted: true} = conn), do: conn
  defp assign_flags(%{assigns: %{database: nil}} = conn), do: conn

  defp assign_flags(conn) do
    database = conn.assigns.database

    conn
    |> assign(:query_stats_enabled, PgHero.Database.query_stats_enabled?(database))
    |> assign(:system_stats_enabled, PgHero.Database.system_stats_enabled?(database))
    |> assign(:replica, PgHero.Database.replica?(database))
    |> assign(:explain_enabled, PgHero.explain_enabled?())
    |> assign(:kill_enabled, PgHero.kill_enabled?())
    |> assign(:show_migrations, PgHero.config().show_migrations)
  end

  defp extra_path(path_info, prefix) do
    prefix_parts = prefix |> String.trim("/") |> String.split("/", trim: true)

    path_info
    |> Enum.drop(length(prefix_parts))
  end

  defp normalize_path("/"), do: ""
  defp normalize_path(path), do: String.trim_trailing(path, "/")
end
