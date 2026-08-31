defmodule PgHeroWeb.Helpers do
  @moduledoc false

  use Phoenix.Component

  def pg_path(conn, rest, params \\ %{})

  def pg_path(conn, rest, params) when is_binary(rest) do
    pg_path(conn, String.split(rest, "/", trim: true), params)
  end

  def pg_path(conn, rest, params) when is_list(rest) do
    prefix = conn.assigns[:pghero_prefix] || "/pghero"
    db = if conn.assigns[:pghero_database_in_path], do: [conn.assigns.database.id], else: []

    path =
      [prefix | db ++ rest]
      |> Enum.join("/")
      |> String.replace(~r{/+}, "/")

    path = if String.starts_with?(path, "/"), do: path, else: "/" <> path
    append_query(path, params)
  end

  def pg_asset_path(conn, file) do
    prefix = conn.assigns[:pghero_prefix] || "/pghero"
    path = Path.join(prefix, "assets/#{file}") |> String.replace(~r{/+}, "/")
    if String.starts_with?(path, "/"), do: path, else: "/" <> path
  end

  def csrf_token(conn) do
    Map.get(conn.private, :plug_session) && Plug.CSRFProtection.get_csrf_token()
  rescue
    _ -> nil
  end

  def pretty_ident(table, schema \\ nil) do
    table_ident = simple_or_quote(table)

    if schema && schema != "public" do
      simple_or_quote(schema) <> "." <> table_ident
    else
      table_ident
    end
  end

  defp simple_or_quote(ident) do
    if Regex.match?(~r/\A[a-z0-9_]+\z/, to_string(ident)) do
      to_string(ident)
    else
      PgHero.Query.quote_ident(ident)
    end
  end

  def js_value(value) do
    value
    |> Jason.encode!(escape: :html_safe)
    |> Phoenix.HTML.raw()
  end

  def number_with_delimiter(n), do: PgHero.Pretty.delimiter(n)

  def pluralize(count, singular, plural \\ nil) do
    word =
      cond do
        count == 1 ->
          singular

        is_binary(plural) ->
          plural

        String.ends_with?(singular, "y") and not String.ends_with?(singular, ~w(ay ey oy uy)) ->
          String.replace_suffix(singular, "y", "ies")

        true ->
          singular <> "s"
      end

    "#{number_with_delimiter(count)} #{word}"
  end

  def remove_index(query) do
    columns =
      case query[:columns] do
        nil -> nil
        [one] -> inspect(one)
        list when is_list(list) -> inspect(list)
      end

    name = query[:name] || query[:index]
    table = query[:table]
    ret = "drop_index(:#{table}, name: #{inspect(to_string(name))}"
    if columns, do: ret <> ", column: #{columns})", else: ret <> ")"
  end

  def latest_time(times) do
    times
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_datetime/1)
    |> Enum.max_by(&DateTime.to_unix(&1, :microsecond), fn -> nil end)
  end

  def time_ago_in_words(nil), do: nil

  def time_ago_in_words(time) do
    seconds = DateTime.diff(DateTime.utc_now(), to_datetime(time), :second) |> abs()

    cond do
      seconds < 60 -> "#{seconds} seconds"
      seconds < 3600 -> "#{div(seconds, 60)} minutes"
      seconds < 86_400 -> "#{div(seconds, 3600)} hours"
      true -> "#{div(seconds, 86_400)} days"
    end
  end

  def format_duration_ms(nil), do: nil

  def format_duration_ms(ms) do
    sec = ms / 1000.0

    cond do
      sec < 60 ->
        :erlang.float_to_binary(sec, decimals: 1) <> " s"

      sec < 86_400 ->
        Calendar.strftime(from_seconds(trunc(sec)), "%H:%M:%S")

      true ->
        days = div(trunc(sec), 86_400)
        rest = rem(trunc(sec), 86_400)
        "#{days}d #{Calendar.strftime(from_seconds(rest), "%H:%M:%S")}"
    end
  end

  def action_name(conn), do: conn.assigns[:pghero_action] || conn.private[:phoenix_action]

  def active_class(conn, action) do
    if action_name(conn) == action, do: "active", else: ""
  end

  def query_hash_hex(hash) when is_integer(hash) do
    <<hash::signed-64>> |> Base.encode16(case: :lower)
  end

  def query_hash_hex(_), do: nil

  def decode_query_hash(value) when is_binary(value) do
    cond do
      String.length(value) == 16 and Regex.match?(~r/\A[0-9a-f]{16}\z/i, value) ->
        case Base.decode16(value, case: :mixed) do
          {:ok, <<hash::signed-64>>} -> hash
          _ -> nil
        end

      Regex.match?(~r/\A-?\d{1,19}\z/, value) ->
        String.to_integer(value)

      true ->
        nil
    end
  end

  def xhr?(conn) do
    "XMLHttpRequest" in Plug.Conn.get_req_header(conn, "x-requested-with")
  end

  defp append_query(path, params) when params == %{} or params == [], do: path

  defp append_query(path, params) do
    filtered =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    case filtered do
      [] -> path
      pairs -> path <> "?" <> URI.encode_query(pairs)
    end
  end

  defp to_datetime(%DateTime{} = dt), do: dt
  defp to_datetime(%NaiveDateTime{} = dt), do: DateTime.from_naive!(dt, "Etc/UTC")

  defp from_seconds(sec) do
    {:ok, time} = Time.new(div(sec, 3600), rem(div(sec, 60), 60), rem(sec, 60))
    time
  end
end
