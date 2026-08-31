defmodule PgHero.IndexesTest do
  use ExUnit.Case, async: true

  alias PgHero.Methods.Indexes

  defp db do
    %PgHero.Database{id: "primary", name: "Primary", config: %{}, conn: nil}
  end

  defp idx(name, columns, opts \\ []) do
    %{
      schema: "public",
      table: "users",
      name: name,
      columns: columns,
      using: "btree",
      unique: Keyword.get(opts, :unique, false),
      primary: Keyword.get(opts, :primary, false),
      valid: true,
      indexprs: nil,
      indpred: nil
    }
  end

  test "index_covers?/2 matches a prefix of indexed columns" do
    assert Indexes.index_covers?(["a", "b", "c"], ["a", "b"])
    refute Indexes.index_covers?(["a", "b"], ["a", "b", "c"])
    refute Indexes.index_covers?(["b", "a"], ["a", "b"])
  end

  test "duplicate_indexes/2 finds an index covered by a wider index" do
    indexes = [
      idx("users_email_idx", ["email"]),
      idx("users_email_created_idx", ["email", "created_at"])
    ]

    dupes = Indexes.duplicate_indexes(db(), indexes: indexes)
    assert [%{unneeded_index: unneeded, covering_index: covering}] = dupes
    assert unneeded.name == "users_email_idx"
    assert covering.name == "users_email_created_idx"
  end

  test "duplicate_indexes/2 treats a non-unique index covered by a primary key as unneeded" do
    indexes = [
      idx("users_pkey", ["id"], primary: true),
      idx("users_id_idx", ["id"])
    ]

    dupes = Indexes.duplicate_indexes(db(), indexes: indexes)
    assert [%{unneeded_index: unneeded, covering_index: covering}] = dupes
    assert unneeded.name == "users_id_idx"
    assert covering.name == "users_pkey"
  end
end
