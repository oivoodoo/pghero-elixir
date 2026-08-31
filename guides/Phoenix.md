# PgHero Phoenix

## Installation

Add PgHero to `mix.exs`:

```elixir
def deps do
  [
    {:pghero, "~> 0.1.0"}
  ]
end
```

Configure a database:

```elixir
config :pghero, repo: MyApp.Repo
```

Mount the dashboard in `router.ex`. Always put it behind authentication in production.

```elixir
import PgHeroWeb.Router

scope "/" do
  pipe_through [:browser, :require_admin]
  pghero "/pghero"
end
```

The host `:browser` pipeline should include `:fetch_session`, `:fetch_flash` or `:fetch_live_flash`, and `:protect_from_forgery`.

## Authentication

### Your own plug (recommended)

```elixir
pipeline :require_admin do
  plug :browser
  plug MyAppWeb.Plugs.RequireAdmin
end

scope "/" do
  pipe_through :require_admin
  pghero "/pghero"
end
```

### HTTP basic auth

```elixir
config :pghero,
  username: System.get_env("PGHERO_USERNAME"),
  password: System.get_env("PGHERO_PASSWORD")
```

## Multiple databases

```elixir
config :pghero,
  databases: [
    primary: [repo: MyApp.Repo],
    replica: [url: System.get_env("REPLICA_DATABASE_URL"), name: "Replica"]
  ]
```

## Historical stats

```elixir
defmodule MyApp.Repo.Migrations.CreatePgheroStats do
  use Ecto.Migration

  def up, do: PgHero.Migrations.up()
  def down, do: PgHero.Migrations.down()
end
```

Then schedule:

```elixir
# every 5 minutes
PgHero.capture_query_stats()

# daily
PgHero.capture_space_stats()
```

## CSP

Inline scripts are used for charts. By default PgHero sets:

```
Content-Security-Policy: default-src 'self' 'unsafe-inline' 'unsafe-eval'
```

Disable that if you set CSP yourself:

```elixir
config :pghero, override_csp: false
```

## Kill queries

Disable kill buttons:

```elixir
config :pghero, disable_kill: true
```

## Explain analyze

Explain is on by default (plan only, rolled back). To allow `EXPLAIN ANALYZE`:

```elixir
config :pghero, explain: "analyze"
```

This runs the query. Only enable it for trusted operators.
