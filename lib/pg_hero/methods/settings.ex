defmodule PgHero.Methods.Settings do
  @moduledoc false

  import PgHero.Query

  def settings(db) do
    names =
      if PgHero.Database.server_version_num(db) >= 180_000 do
        [
          :max_connections,
          :shared_buffers,
          :effective_cache_size,
          :maintenance_work_mem,
          :checkpoint_completion_target,
          :wal_buffers,
          :default_statistics_target,
          :random_page_cost,
          :effective_io_concurrency,
          :work_mem,
          :huge_pages,
          :jit,
          :wal_compression,
          :io_method,
          :min_wal_size,
          :max_wal_size
        ]
      else
        [
          :max_connections,
          :shared_buffers,
          :effective_cache_size,
          :maintenance_work_mem,
          :checkpoint_completion_target,
          :wal_buffers,
          :default_statistics_target,
          :random_page_cost,
          :effective_io_concurrency,
          :work_mem,
          :huge_pages,
          :jit,
          :wal_compression,
          :min_wal_size,
          :max_wal_size
        ]
      end

    fetch_settings(db, names)
  end

  def autovacuum_settings(db) do
    fetch_settings(db, [
      :autovacuum,
      :autovacuum_max_workers,
      :autovacuum_vacuum_cost_limit,
      :autovacuum_vacuum_scale_factor,
      :autovacuum_analyze_scale_factor
    ])
  end

  def vacuum_settings(db) do
    fetch_settings(db, [:vacuum_cost_limit])
  end

  defp fetch_settings(db, names) do
    Map.new(names, fn name -> {name, select_one(db, "SHOW #{name}")} end)
  end
end
