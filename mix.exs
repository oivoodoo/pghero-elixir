defmodule PgHero.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/oivoodoo/pghero-elixir"

  def project do
    [
      app: :pghero,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description:
        "A performance dashboard for Postgres. Elixir port of PgHero: mount it in Phoenix or run it standalone with Docker.",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets, :crypto],
      mod: {PgHero.Application, []}
    ]
  end

  defp releases do
    [
      pghero: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 0.20 or ~> 1.0"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.17"},
      {:ecto_sql, "~> 3.11"},
      {:bandit, "~> 1.5"},
      {:plug_cowboy, "~> 2.6", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "pghero",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Original Ruby PgHero" => "https://github.com/ankane/pghero"
      },
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE.txt CHANGELOG.md guides)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md", "guides/Phoenix.md", "guides/Docker.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
