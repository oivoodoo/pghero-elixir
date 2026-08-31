defmodule PgHero.Methods.Replication do
  @moduledoc false

  import PgHero.Query

  def replica?(db) do
    select_one(db, "SELECT pg_is_in_recovery()") == true
  end

  def replication_lag(db) do
    with_feature_support(fn ->
      select_one(db, """
      SELECT
        CASE
          WHEN NOT pg_is_in_recovery() OR pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0
          ELSE EXTRACT (EPOCH FROM NOW() - pg_last_xact_replay_timestamp())
        END
      AS replication_lag
      """)
    end)
  end

  def replication_slots(db) do
    with_feature_support(
      fn ->
        select_all(db, """
        SELECT
          slot_name,
          database,
          active
        FROM pg_replication_slots
        """)
      end,
      []
    )
  end

  def replicating?(db) do
    with_feature_support(
      fn ->
        db |> select_all("SELECT state FROM pg_stat_replication") |> Enum.any?()
      end,
      false
    )
  end

  defp with_feature_support(fun, default \\ nil) do
    fun.()
  rescue
    e in Postgrex.Error ->
      message = Exception.message(e)

      if String.starts_with?(message, "ERROR 0A000") or
           String.contains?(message, "feature is not supported") do
        default
      else
        reraise e, __STACKTRACE__
      end
  end
end
