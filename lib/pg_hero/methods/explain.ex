defmodule PgHero.Methods.Explain do
  @moduledoc false

  import PgHero.Query

  def explain(db, sql, opts \\ []) do
    options = []
    options = add_option(options, "ANALYZE", opts[:analyze])
    options = add_option(options, "VERBOSE", opts[:verbose])
    options = add_option(options, "SETTINGS", opts[:settings])
    options = add_option(options, "GENERIC_PLAN", opts[:generic_plan])
    options = add_option(options, "COSTS", opts[:costs])
    options = add_option(options, "BUFFERS", opts[:buffers])
    options = add_option(options, "WAL", opts[:wal])
    options = add_option(options, "TIMING", opts[:timing])
    options = add_option(options, "SUMMARY", opts[:summary])
    options = options ++ ["FORMAT #{explain_format(opts[:format] || "text")}"]

    wrapped = "(#{Enum.join(options, ", ")}) #{sql}"
    timeout_ms = round(PgHero.Database.explain_timeout_sec(db) * 1000)

    with_transaction(
      db,
      fn conn ->
        db = %{db | conn: conn}

        if unsafe_statement?(sql) and not explain_safe?(db) do
          raise Postgrex.Error, message: "Unsafe statement"
        end

        # Simple query protocol so $1/$2 placeholders from pg_stat_statements
        # are sent to Postgres instead of being bound by Postgrex.
        result = execute(db, "EXPLAIN #{wrapped}", [], query_type: :text)
        Enum.map_join(result.rows, "\n", fn [plan | _] -> plan end)
      end,
      statement_timeout: timeout_ms,
      rollback: true
    )
  end

  defp unsafe_statement?(sql) do
    stripped = sql |> String.trim_trailing() |> String.trim_trailing(";")
    String.contains?(stripped, ";") or String.contains?(String.upcase(sql), "COMMIT")
  end

  defp explain_safe?(db) do
    execute(db, "SELECT 1; SELECT 1", [], query_type: :text)
    false
  rescue
    _ in Postgrex.Error -> true
  end

  defp add_option(options, _name, nil), do: options
  defp add_option(options, name, true), do: options ++ [name]
  defp add_option(options, name, false), do: options ++ ["#{name} FALSE"]

  defp explain_format(format) when format in ["text", "xml", "json", "yaml"],
    do: String.upcase(format)

  defp explain_format(_), do: raise(ArgumentError, "Unknown format")
end
