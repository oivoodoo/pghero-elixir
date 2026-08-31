import Config

config :phoenix, :json_library, Jason

config :pghero, :standalone, false

config :pghero, PgHero.Standalone.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PgHero.Standalone.ErrorHTML],
    layout: false
  ],
  pubsub_server: PgHero.PubSub,
  live_view: [signing_salt: "pghero_lv"],
  server: false

import_config "#{config_env()}.exs"
