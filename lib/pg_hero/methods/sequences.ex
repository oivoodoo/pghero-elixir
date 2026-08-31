defmodule PgHero.Methods.Sequences do
  @moduledoc false

  import PgHero.Query

  def sequences(db) do
    sequences =
      select_all(db, """
      SELECT
        sn.nspname AS schema,
        s.relname AS sequence,
        n.nspname AS table_schema,
        c.relname AS table,
        attname AS column,
        format_type(a.atttypid, a.atttypmod) AS column_type,
        pg_get_expr(d.adbin, d.adrelid) AS default_value
      FROM
        pg_catalog.pg_attribute a
      INNER JOIN
        pg_catalog.pg_class c ON c.oid = a.attrelid
      INNER JOIN
        pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN
        pg_catalog.pg_depend dep ON dep.refclassid = 'pg_catalog.pg_class'::regclass
        AND dep.refobjid = a.attrelid
        AND dep.refobjsubid = a.attnum
        AND dep.classid = 'pg_catalog.pg_class'::regclass
        AND dep.objsubid = 0
        AND dep.deptype IN ('i', 'a')
        AND dep.objid IN (SELECT oid FROM pg_class WHERE relkind = 'S')
      LEFT JOIN
        pg_catalog.pg_class s ON s.oid = dep.objid
      LEFT JOIN
        pg_catalog.pg_namespace sn ON sn.oid = s.relnamespace
      LEFT JOIN
        pg_catalog.pg_attrdef d ON a.attrelid = d.adrelid
        AND a.attnum = d.adnum
        AND s.relkind IS NULL
      WHERE
        NOT a.attisdropped
        AND a.attnum > 0
        AND (pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval%' OR s.relname IS NOT NULL)
        AND c.relpersistence <> 't'
      """)

    sequences =
      Enum.map(sequences, fn column ->
        max_value =
          case column[:column_type] do
            "smallint" -> 32_767
            "integer" -> 2_147_483_647
            _ -> 9_223_372_036_854_775_807
          end

        column = Map.put(column, :max_value, max_value)

        if column[:sequence] do
          Map.delete(column, :default_value)
        else
          {schema, sequence} = parse_default_value(column[:default_value])

          column
          |> Map.put(:schema, schema || column[:schema])
          |> Map.put(:sequence, sequence)
          |> then(fn col -> if sequence, do: Map.delete(col, :default_value), else: col end)
        end
      end)

    sequences = add_sequence_attributes(db, sequences)

    last_value =
      db
      |> select_all(
        "SELECT schemaname AS schema, sequencename AS sequence, COALESCE(last_value, start_value) AS last_value FROM pg_sequences"
      )
      |> Map.new(fn row -> {{row[:schema], row[:sequence]}, row[:last_value]} end)

    sequences
    |> Enum.map(fn seq ->
      if seq[:readable] do
        Map.put(seq, :last_value, last_value[{seq[:schema], seq[:sequence]}])
      else
        seq
      end
    end)
    |> Enum.sort_by(fn s -> to_string(s[:sequence]) end)
  end

  def sequence_danger(db, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.9)
    sequences = opts[:sequences] || sequences(db)

    sequences
    |> Enum.filter(fn s -> s[:last_value] && s[:last_value] / s[:max_value] > threshold end)
    |> Enum.sort_by(fn s -> s[:max_value] - s[:last_value] end)
  end

  defp parse_default_value(nil), do: {nil, nil}

  defp parse_default_value(default_value) do
    cond do
      match = Regex.run(~r/\Anextval\('(.+)'\:\:regclass\)\z/, default_value) ->
        unquote_ident_pair(Enum.at(match, 1))

      match = Regex.run(~r/\Anextval\(\('(.+)'\:\:text\)\:\:regclass\)\z/, default_value) ->
        unquote_ident_pair(Enum.at(match, 1))

      true ->
        {nil, nil}
    end
  end

  defp unquote_ident_pair(value) do
    case String.split(value, ".") do
      [seq] -> {nil, unquote_ident(seq)}
      [schema, seq] -> {unquote_ident(schema), unquote_ident(seq)}
      _ -> {nil, nil}
    end
  end

  defp add_sequence_attributes(db, sequences) do
    sequence_attributes =
      select_all(db, """
      SELECT
        n.nspname AS schema,
        c.relname AS sequence,
        has_sequence_privilege(c.oid, 'SELECT') AND (c.relpersistence <> 'u' OR NOT pg_is_in_recovery()) AS readable
      FROM
        pg_class c
      INNER JOIN
        pg_catalog.pg_namespace n ON n.oid = c.relnamespace
      WHERE
        c.relkind = 'S'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      """)

    sequences =
      Enum.map(sequences, fn sequence ->
        if is_nil(sequence[:schema]) and sequence[:sequence] do
          schemas =
            Enum.filter(sequence_attributes, fn s -> s[:sequence] == sequence[:sequence] end)

          case schemas do
            [only] -> Map.put(sequence, :schema, only[:schema])
            _ -> sequence
          end
        else
          sequence
        end
      end)

    readable =
      Map.new(sequence_attributes, fn s -> {{s[:schema], s[:sequence]}, s[:readable]} end)

    Enum.map(sequences, fn sequence ->
      Map.put(sequence, :readable, readable[{sequence[:schema], sequence[:sequence]}] || false)
    end)
  end
end
