defmodule PgHero.ConfigTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.get_all_env(:pghero)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:pghero) do
        Application.delete_env(:pghero, key)
      end

      for {key, value} <- original do
        Application.put_env(:pghero, key, value)
      end
    end)

    :ok
  end

  test "defaults to empty databases without repo or url" do
    Application.delete_env(:pghero, :repo)
    Application.delete_env(:pghero, :url)
    Application.delete_env(:pghero, :databases)
    System.delete_env("DATABASE_URL")
    System.delete_env("PGHERO_DATABASE_URL")

    assert PgHero.Config.get().databases == %{}
  end

  test "builds a database from DATABASE_URL" do
    Application.delete_env(:pghero, :repo)
    Application.delete_env(:pghero, :url)
    Application.delete_env(:pghero, :databases)
    System.put_env("DATABASE_URL", "postgres://app:secret@db.internal:5432/app_prod")

    on_exit(fn -> System.delete_env("DATABASE_URL") end)

    assert %{primary: cfg} = PgHero.Config.get().databases
    assert cfg[:url] == "postgres://app:secret@db.internal:5432/app_prod"
    assert cfg[:id] == "primary"
  end

  test "builds a single database from repo" do
    Application.put_env(:pghero, :repo, MyApp.Repo)
    Application.delete_env(:pghero, :databases)

    assert %{primary: cfg} = PgHero.Config.get().databases
    assert cfg[:repo] == MyApp.Repo
    assert cfg[:id] == "primary"
  end

  test "builds multiple databases" do
    Application.put_env(:pghero, :databases,
      primary: [repo: Primary.Repo],
      replica: [url: "postgres://localhost/replica", name: "Replica"]
    )

    databases = PgHero.Config.get().databases

    assert databases["primary"][:repo] == Primary.Repo or
             databases[:primary][:repo] == Primary.Repo

    replica = databases[:replica] || databases["replica"]
    assert replica[:name] == "Replica"
  end

  test "explain and kill flags" do
    Application.put_env(:pghero, :explain, false)
    Application.put_env(:pghero, :disable_kill, true)
    refute PgHero.explain_enabled?()
    refute PgHero.kill_enabled?()
  end
end
