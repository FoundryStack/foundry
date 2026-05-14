defmodule Mix.Tasks.Foundry.Studio do
  @shortdoc "Launch Foundry Studio on an open localhost port"

  @moduledoc """
  Starts the Foundry Studio web runtime for the current target project.

      mix foundry.studio
      mix foundry.studio --project ../my_app --port auto
      mix foundry.studio --no-browser
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    launch_opts =
      case Foundry.Studio.parse_studio_argv(["studio" | args]) do
        {:ok, parsed} -> parsed
        {:error, message} -> Mix.raise(message)
        :no_command -> Mix.raise("Expected `studio` launch arguments.")
      end

    result = Foundry.Studio.launch(launch_opts)

    case result do
      {:ok, %{url: url, reused?: true}} ->
        Mix.shell().info("Foundry Studio already running at #{url}")

      {:ok, %{url: url, port: selected_port}} ->
        Mix.shell().info("Foundry Studio listening on #{url} (port #{selected_port})")

      {:error, {:port_unavailable, selected_port}} ->
        Mix.raise("Port #{selected_port} is not available.")

      {:error, {:health_timeout, selected_port}} ->
        Mix.raise("Foundry Studio did not become healthy on port #{selected_port}.")

      {:error, reason} ->
        Mix.raise("Failed to launch Foundry Studio: #{inspect(reason)}")
    end

    unless match?({:ok, %{reused?: true}}, result) do
      Process.sleep(:infinity)
    end
  end
end
