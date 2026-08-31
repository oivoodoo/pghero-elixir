defmodule PgHero.Standalone do
  @moduledoc false

  def enabled? do
    Application.get_env(:pghero, :standalone, false) == true or
      System.get_env("PGHERO_SERVER") in ["1", "true"]
  end

  def children do
    if enabled?() do
      [
        {Phoenix.PubSub, name: PgHero.PubSub},
        PgHero.Standalone.Endpoint
      ]
    else
      []
    end
  end

  def configure!(opts \\ []) do
    port = Keyword.get(opts, :port) || env_int("PORT", 8080)
    secret = System.get_env("SECRET_KEY_BASE") || random_secret()
    url = System.get_env("DATABASE_URL") || System.get_env("PGHERO_DATABASE_URL")

    Application.put_env(:pghero, :standalone, true)
    if is_binary(url) and url != "", do: Application.put_env(:pghero, :url, url)

    endpoint = Application.get_env(:pghero, PgHero.Standalone.Endpoint, [])

    Application.put_env(
      :pghero,
      PgHero.Standalone.Endpoint,
      Keyword.merge(endpoint,
        http: [ip: {0, 0, 0, 0}, port: port],
        secret_key_base: secret,
        server: true,
        url: [host: System.get_env("PHX_HOST") || "localhost", port: port]
      )
    )

    :ok
  end

  defp env_int(name, default) do
    case System.get_env(name) do
      nil -> default
      "" -> default
      value -> String.to_integer(value)
    end
  end

  defp random_secret do
    48 |> :crypto.strong_rand_bytes() |> Base.encode64()
  end
end
