defmodule PhoenixLLMChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_llm_chat,
      name: "phoenix_llm_chat",
      source_url: "https://github.com/FoundryStack/phoenix_llm_chat",
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  defp description() do
    "An extensible Phoenix LiveView chat component with streaming LLM support and multi-session management."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/FoundryStack/phoenix_llm_chat"
      }
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:req, "~> 0.5"}
    ]
  end
end
