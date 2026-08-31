defmodule PgHero.Integration do
  @moduledoc false

  def skip_reason do
    case System.get_env("DATABASE_URL") do
      url when is_binary(url) and url != "" -> false
      _ -> "DATABASE_URL is not set"
    end
  end

  def url do
    System.get_env("DATABASE_URL")
  end

  def postgrex_opts(url) do
    uri = URI.parse(url)
    {user, password} = userinfo(uri)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user || "postgres",
      password: password || "postgres",
      database: String.trim_leading(uri.path || "/postgres", "/")
    ]
  end

  defp userinfo(%URI{userinfo: nil}), do: {nil, nil}

  defp userinfo(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {user, nil}
      [user, password] -> {user, password}
    end
  end
end
