defmodule PgHeroWeb.HelpersTest do
  use ExUnit.Case, async: true

  alias PgHeroWeb.Helpers

  test "pretty_ident/2 quotes non-simple names" do
    assert Helpers.pretty_ident("users") == "users"
    assert Helpers.pretty_ident("users", "public") == "users"
    assert Helpers.pretty_ident("users", "app") == "app.users"
    assert Helpers.pretty_ident("User Table") == "\"User Table\""
  end

  test "query_hash hex round-trips signed 64-bit values" do
    hash = -4_223_372_036_854_775_808
    hex = Helpers.query_hash_hex(hash)
    assert String.length(hex) == 16
    assert Helpers.decode_query_hash(hex) == hash
  end

  test "pluralize/3" do
    assert Helpers.pluralize(1, "query") == "1 query"
    assert Helpers.pluralize(2, "query") == "2 queries"
    assert Helpers.pluralize(2, "index", "indexes") == "2 indexes"
  end

  test "format_duration_ms/1" do
    assert Helpers.format_duration_ms(1500) == "1.5 s"
    assert Helpers.format_duration_ms(90_000) == "00:01:30"
  end

  test "pg_asset_path/2 uses the assigned prefix" do
    conn = %Plug.Conn{assigns: %{pghero_prefix: "/dev/internal/pghero"}}

    assert Helpers.pg_asset_path(conn, "application.css") ==
             "/dev/internal/pghero/assets/application.css"

    assert Helpers.pg_path(conn, "queries") == "/dev/internal/pghero/queries"
  end
end
