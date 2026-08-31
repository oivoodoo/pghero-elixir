defmodule PgHero.PrettyTest do
  use ExUnit.Case, async: true

  alias PgHero.Pretty

  test "formats byte sizes" do
    assert Pretty.size(0) == "0 Bytes"
    assert Pretty.size(500) == "500 Bytes"
    assert Pretty.size(1024) == "1 KB"
    assert Pretty.size(1536) == "1.5 KB"
    assert Pretty.size(1024 * 1024) == "1 MB"
    assert Pretty.size(-2048) == "-2 KB"
  end

  test "formats integers with delimiters" do
    assert Pretty.delimiter(12) == "12"
    assert Pretty.delimiter(1234) == "1,234"
    assert Pretty.delimiter(1_234_567) == "1,234,567"
    assert Pretty.delimiter(-99_000) == "-99,000"
  end
end
