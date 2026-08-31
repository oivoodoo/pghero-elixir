import Config

config :pghero, PgHero.TestEndpoint,
  secret_key_base: String.duplicate("abcdefghijklmnopqrstuvwxyz012345", 2),
  server: false,
  http: [port: 4002],
  live_view: [signing_salt: "pgherotest"]

config :logger, level: :warning

# Tests start their own Postgrex clients. CI sets DATABASE_URL, which would
# otherwise start a named pool in PgHero.Application and collide with setup.
config :pghero, start_connections: false
