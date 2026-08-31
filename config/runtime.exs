import Config

if config_env() != :test and System.get_env("PGHERO_SERVER") in ["1", "true"] do
  port = String.to_integer(System.get_env("PORT") || "8080")

  secret =
    System.get_env("SECRET_KEY_BASE") ||
      48 |> :crypto.strong_rand_bytes() |> Base.encode64()

  url = System.get_env("DATABASE_URL") || System.get_env("PGHERO_DATABASE_URL")

  config :pghero, :standalone, true
  if is_binary(url) and url != "", do: config(:pghero, :url, url)

  config :pghero, PgHero.Standalone.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret,
    server: true,
    url: [host: System.get_env("PHX_HOST") || "localhost", port: port]
end
