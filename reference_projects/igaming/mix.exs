defmodule IgamingRef.MixProject do
  use Mix.Project

  def project do
    [
      app: :igaming_ref,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {IgamingRef.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core Ash stack — upgraded to 3.20 for Foundry compatibility
      {:ash, "~> 3.20"},
      {:ash_postgres, "~> 2.0"},
      {:spark, "~> 2.0"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},

      # Phoenix
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:bandit, "~> 1.2"},
      {:plug_cowboy, "~> 2.6"},

      # Ash extensions
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_state_machine, "~> 0.2"},
      {:ash_paper_trail, "~> 0.1"},
      {:ash_archival, "~> 2.0"},
      {:ash_json_api, "~> 1.0"},

      # Reactor — upgraded to 1.0 (stable release) from 0.10
      {:reactor, "~> 1.0"},

      # Money
      {:ash_money, "~> 0.1"},
      {:ex_money, "~> 5.15"},
      {:ex_money_sql, "~> 1.7"},
      {:ex_cldr, "~> 2.0"},

      # Feature flags (runtime: false — no Redis; configure Ecto persistence when needed)
      {:fun_with_flags, "~> 1.11", runtime: false},
      {:fun_with_flags_ui, "~> 1.0", runtime: false},

      # Background jobs
      {:oban, "~> 2.17"},
      {:ash_oban, "~> 0.2"},

      # Rate limiting (runtime: false — configure when needed)
      {:hammer, "~> 7.0", runtime: false},

      # Observability
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},

      # Igniter — upgraded for Ash 3.20 compatibility
      {:igniter, "~> 0.6"},

      # Foundry — meta-framework for governance
      {:foundry_stack, "~> 0.1.1"},

      # Server-Driven UI
      {:ash_sdui, "~> 0.1"},

      # Serialisation
      {:jason, "~> 1.4"},

      # Testing
      {:stream_data, "~> 1.0"},
      {:bypass, "~> 2.1", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:ex_machina, "~> 2.7", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},

      # Dependency conflict resolution
      {:plug, "~> 1.7", override: true},

      # Transitive dependencies for Swoosh email client
      {:hackney, "~> 1.9"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "run priv/repo/seeds.exs"],
      "ash.setup": ["ash.create", "ash.migrate"],
      "ash.reset": ["ash.drop", "ash.setup"],
      test: ["ash.migrate --quiet", "test"]
    ]
  end
end
