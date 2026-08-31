# Dummy Phoenix app

A host application used to try the PgHero Phoenix mount.

## Run

From this directory:

```sh
docker compose up -d
mix setup
mix phx.server
```

Then open:

- [http://localhost:4000](http://localhost:4000) — dummy home
- [http://localhost:4000/pghero](http://localhost:4000/pghero) — dashboard

The important wiring is:

```elixir
# config/config.exs
config :pghero, repo: Dummy.Repo

# lib/dummy_web/router.ex
import PgHeroWeb.Router

scope "/" do
  pipe_through :browser
  pghero "/pghero"
end
```
