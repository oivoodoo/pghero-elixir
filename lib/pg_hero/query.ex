defmodule PgHero.Query do
  @moduledoc false

  @timeout_codes [:lock_not_available, :query_canceled, :idle_in_transaction_session_timeout]

  def select_all(db, sql, params \\ [], opts \\ []) do
    sql = squish(sql)
    result = run(db, sql, params, opts)

    rows =
      result.rows
      |> Enum.map(fn row ->
        result.columns
        |> Enum.map(&column_atom/1)
        |> Enum.zip(Enum.map(row, &normalize/1))
        |> Map.new()
      end)

    if Keyword.get(opts, :stats) do
      rows
    else
      rows
    end
  end

  def select_all_size(db, sql, params \\ []) do
    db
    |> select_all(sql, params)
    |> Enum.map(fn row ->
      Map.put(row, :size, PgHero.Pretty.size(row[:size_bytes]))
    end)
  end

  def select_one(db, sql, params \\ [], opts \\ []) do
    case select_all(db, sql, params, opts) do
      [row | _] ->
        row |> Map.values() |> List.first()

      [] ->
        nil
    end
  end

  def execute(db, sql, params \\ [], opts \\ []) do
    run(db, squish(sql), params, opts)
  end

  def with_transaction(db, fun, opts \\ []) do
    lock_timeout = Keyword.get(opts, :lock_timeout)
    statement_timeout = Keyword.get(opts, :statement_timeout)
    rollback? = Keyword.get(opts, :rollback, false)

    wrap = fn conn ->
      if statement_timeout,
        do: query!(conn, "SET LOCAL statement_timeout = #{int!(statement_timeout)}")

      if lock_timeout, do: query!(conn, "SET LOCAL lock_timeout = #{int!(lock_timeout)}")
      result = fun.(conn)

      if rollback? do
        rollback(conn, result)
      else
        result
      end
    end

    case conn_spec(db, opts) do
      {:repo, repo} ->
        case repo.transaction(fn -> wrap.({:repo, repo}) end) do
          {:ok, result} -> result
          {:error, result} -> result
        end

      {:pid, pid} ->
        case Postgrex.transaction(pid, fn conn -> wrap.({:pid, conn}) end) do
          {:ok, result} -> result
          {:error, result} -> result
        end
    end
  end

  def timeout_error?(%Postgrex.Error{postgres: %{code: code}}) when code in @timeout_codes,
    do: true

  def timeout_error?(%DBConnection.ConnectionError{}), do: true
  def timeout_error?(_), do: false

  def quote_ident(value) when is_atom(value), do: quote_ident(Atom.to_string(value))

  def quote_ident(value) when is_binary(value) do
    "\"" <> String.replace(value, "\"", "\"\"") <> "\""
  end

  def quote_table_name(value) when is_binary(value) do
    value
    |> String.split(".", parts: 2)
    |> Enum.map_join(".", &quote_ident/1)
  end

  def unquote_ident(nil), do: nil

  def unquote_ident(<<"\"", rest::binary>>) do
    String.trim_trailing(rest, "\"")
  end

  def unquote_ident(part), do: part

  defp run(db, sql, params, opts) do
    retries = 0
    do_run(conn_spec(db, opts), sql, params, retries)
  end

  defp do_run(spec, sql, params, retries) do
    query!(spec, sql, params)
  rescue
    e in Postgrex.Error ->
      message = Exception.message(e)

      if String.contains?(message, "internal error") and retries < 2 do
        Process.sleep(100)
        do_run(spec, sql, params, retries + 1)
      else
        reraise e, __STACKTRACE__
      end
  end

  defp query!(spec, sql, params \\ [])

  defp query!({:repo, repo}, sql, params) do
    Ecto.Adapters.SQL.query!(repo, sql, params)
  end

  defp query!({:pid, pid}, sql, params) do
    Postgrex.query!(pid, sql, params)
  end

  defp rollback({:repo, repo}, result), do: repo.rollback(result)
  defp rollback({:pid, conn}, result), do: Postgrex.rollback(conn, result)

  defp conn_spec(db, opts) do
    if Keyword.get(opts, :stats) do
      stats_spec(db)
    else
      db.conn
    end
  end

  defp stats_spec(db) do
    case PgHero.config().stats_database_url do
      url when is_binary(url) and url != "" ->
        {:pid, PgHero.Config.stats_connection_name()}

      _ ->
        db.conn
    end
  end

  defp squish(sql) do
    sql
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp column_atom(col) when is_atom(col), do: col
  defp column_atom(col) when is_binary(col), do: String.to_atom(col)

  defp normalize(%Decimal{} = d) do
    Decimal.to_float(d)
  end

  defp normalize(%Postgrex.Interval{} = interval) do
    months = interval.months
    days = interval.days
    secs = interval.secs
    micro = Map.get(interval, :microsecs, 0)
    months * 30 * 86_400 + days * 86_400 + secs + micro / 1_000_000
  end

  defp normalize(other), do: other

  defp int!(n) when is_integer(n), do: n
  defp int!(n) when is_float(n), do: round(n)
end
