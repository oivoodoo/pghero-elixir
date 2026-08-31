# Contributing

1. Fork and clone the repo
2. `mix deps.get`
3. `mix test`

Integration tests need Postgres 14+:

```sh
DATABASE_URL=postgres://postgres:postgres@localhost/pghero_test mix test
```

Format before opening a PR:

```sh
mix format
```
