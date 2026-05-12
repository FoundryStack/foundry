defmodule PhoenixLLMChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_llm_chat,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

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
