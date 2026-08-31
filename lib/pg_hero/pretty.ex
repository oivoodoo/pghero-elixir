defmodule PgHero.Pretty do
  @moduledoc false

  @units ["Bytes", "KB", "MB", "GB", "TB", "PB", "EB"]

  def size(nil), do: nil

  def size(%Decimal{} = bytes) do
    bytes |> Decimal.to_float() |> round() |> size()
  end

  def size(bytes) when is_float(bytes), do: size(round(bytes))

  def size(bytes) when is_integer(bytes) and bytes < 0 do
    "-" <> size(-bytes)
  end

  def size(bytes) when is_integer(bytes) do
    {value, unit} = human_size(bytes * 1.0, 0)
    formatted = format_number(value)
    "#{formatted} #{unit}"
  end

  def delimiter(nil), do: nil

  def delimiter(%Decimal{} = n), do: n |> Decimal.to_float() |> delimiter()

  def delimiter(n) when is_float(n) do
    truncated = trunc(n)

    if truncated == n do
      delimiter(truncated)
    else
      int_part = delimiter(truncated)
      frac = n - truncated
      frac_str = frac |> :erlang.float_to_binary(decimals: 1) |> String.replace_prefix("0", "")
      int_part <> frac_str
    end
  end

  def delimiter(n) when is_integer(n) and n < 0, do: "-" <> delimiter(-n)

  def delimiter(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def percentage(value, precision: precision) do
    :erlang.float_to_binary(value * 1.0, decimals: precision) <> "%"
  end

  defp human_size(bytes, idx) when idx >= length(@units) - 1 do
    {bytes, Enum.at(@units, idx)}
  end

  defp human_size(bytes, idx) when bytes < 1024 do
    {bytes, Enum.at(@units, idx)}
  end

  defp human_size(bytes, idx) do
    human_size(bytes / 1024, idx + 1)
  end

  defp format_number(n) when n == trunc(n), do: Integer.to_string(trunc(n))

  defp format_number(n) do
    rounded = Float.round(n, 3)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 3)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
    end
  end
end
