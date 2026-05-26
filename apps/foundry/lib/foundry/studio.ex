defmodule Foundry.Studio do
  @moduledoc """
  Launch helpers for the local Foundry Studio runtime.

  This module owns the standalone runtime contract used by `mix foundry.studio`
  and future packaged entrypoints.
  """

  @default_port 4000
  @health_timeout_ms 15_000
  @health_poll_ms 100
  @switches [project: :string, port: :string, no_browser: :boolean]

  @spec launch(keyword()) :: {:ok, map()} | {:error, term()}
  def launch(opts \\ []) do
    with {:ok, launch} <- prepare_launch(opts),
         :ok <- configure_runtime(launch.project_root),
         {:ok, _apps} <- Application.ensure_all_started(:foundry_web),
         :ok <- finalize_launch(launch) do
      {:ok, launch}
    end
  end

  @spec parse_studio_argv([String.t()]) :: {:ok, keyword()} | {:error, String.t()} | :no_command
  def parse_studio_argv(["studio" | args]) do
    {opts, _rest, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      invalid != [] ->
        {:error, "Invalid options: #{inspect(invalid)}"}

      true ->
        with {:ok, port} <- parse_port_option(Keyword.get(opts, :port, "auto")) do
          {:ok,
           [
             project_root: Keyword.get(opts, :project, File.cwd!()),
             port: port,
             open_browser?: !Keyword.get(opts, :no_browser, false)
           ]}
        end
    end
  end

  def parse_studio_argv(_argv), do: :no_command

  @spec mix_task_invoked?(String.t(), keyword()) :: boolean()
  def mix_task_invoked?(task_name, opts \\ []) when is_binary(task_name) do
    argv = Keyword.get(opts, :argv, System.argv())

    plain_args =
      Keyword.get(opts, :plain_args, :init.get_plain_arguments())
      |> Enum.map(&List.to_string/1)

    task_args? = fn args ->
      Enum.chunk_every(args, 2, 1, :discard)
      |> Enum.any?(fn
        [mix_command, ^task_name] when is_binary(mix_command) ->
          Path.basename(mix_command) == "mix"

        _other ->
          false
      end)
    end

    match?([^task_name | _], argv) or task_args?.(argv) or task_args?.(plain_args)
  end

  @spec prepare_launch(keyword()) :: {:ok, map()} | {:error, term()}
  def prepare_launch(opts) do
    project_root = Keyword.get(opts, :project_root, File.cwd!()) |> Path.expand()
    open_browser? = Keyword.get(opts, :open_browser?, true)

    with {:ok, selected} <- select_port(Keyword.get(opts, :port, :auto)) do
      {:ok,
       %{
         open_browser?: open_browser?,
         port: selected.port,
         project_root: project_root,
         reused?: selected.reused?,
         url: url_for_port(selected.port)
       }}
    end
  end

  @spec configure_runtime(String.t()) :: :ok
  def configure_runtime(project_root) when is_binary(project_root) do
    # Only set FOUNDRY_STANDALONE=1 when not already explicitly set by the environment.
    # In cloud mode, the container sets FOUNDRY_STANDALONE=0 and we must not overwrite it —
    # doing so causes clone_project to use System.user_home!() (/home/foundry) instead of
    # /app/projects, which fails because /home/foundry doesn't exist in the container.
    if System.get_env("FOUNDRY_STANDALONE") == nil do
      System.put_env("FOUNDRY_STANDALONE", "1")
    end

    if System.get_env("FOUNDRY_STANDALONE") == "1" do
      System.put_env("PHX_SERVER", "1")
    end

    Application.put_env(:foundry, :current_project_root, project_root)
    Application.put_env(:foundry, :igaming_project_root, project_root)
    Application.put_env(:foundry_web, :current_project_root, project_root)
    Application.put_env(:foundry_web, :igaming_project_root, project_root)
    :ok
  end

  @spec finalize_launch(map()) :: :ok | {:error, term()}
  def finalize_launch(%{port: port, open_browser?: open_browser?, url: url}) do
    with :ok <- wait_for_health(port),
         :ok <- write_port_file(port) do
      if open_browser? do
        open_browser(url)
      end

      :ok
    end
  end

  @spec complete_reused_launch(map()) :: :ok
  def complete_reused_launch(%{open_browser?: open_browser?, url: url}) do
    if open_browser? do
      open_browser(url)
    end

    :ok
  end

  @spec find_open_port(pos_integer()) :: {:ok, pos_integer()} | {:error, :no_open_port}
  def find_open_port(start_port \\ @default_port)
      when is_integer(start_port) and start_port > 0 do
    do_find_open_port(start_port, 100)
  end

  @spec resolve_generic_server_port() :: {:ok, pos_integer()} | {:error, :no_open_port}
  def resolve_generic_server_port do
    cond do
      port_available?(@default_port) ->
        {:ok, @default_port}

      true ->
        case read_port_file() do
          {:ok, port} when port > 0 and port != @default_port ->
            if port_available?(port) do
              {:ok, port}
            else
              find_open_port(@default_port)
            end

          _ ->
            find_open_port(@default_port)
        end
    end
  end

  @spec port_file_path() :: String.t()
  def port_file_path do
    home_dir = System.get_env("FOUNDRY_HOME") || System.user_home!()
    Path.join(home_dir, ".foundry.port")
  end

  @spec read_port_file() :: {:ok, pos_integer()} | {:error, term()}
  def read_port_file do
    case File.read(port_file_path()) do
      {:ok, contents} ->
        contents
        |> String.trim()
        |> Integer.parse()
        |> case do
          {port, ""} when port > 0 -> {:ok, port}
          _ -> {:error, :invalid_port}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec write_port_file(pos_integer()) :: :ok | {:error, term()}
  def write_port_file(port) when is_integer(port) and port > 0 do
    File.write(port_file_path(), "#{port}\n")
  end

  @spec healthy_port?(pos_integer()) :: boolean()
  def healthy_port?(port) when is_integer(port) and port > 0 do
    request = "GET /healthz HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"

    with {:ok, socket} <-
           :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000),
         :ok <- :gen_tcp.send(socket, request),
         {:ok, response} <- :gen_tcp.recv(socket, 0, 1_000) do
      :gen_tcp.close(socket)

      String.starts_with?(response, "HTTP/1.1 200") or
        String.starts_with?(response, "HTTP/1.0 200")
    else
      _ ->
        false
    end
  end

  @spec open_browser(String.t()) :: :ok
  def open_browser(url) do
    case browser_command(url) do
      nil ->
        :ok

      {command, args} ->
        _ = System.cmd(command, args, stderr_to_stdout: true)
        :ok
    end
  end

  @spec url_for_port(pos_integer()) :: String.t()
  def url_for_port(port), do: "http://127.0.0.1:#{port}"

  defp select_port(:auto) do
    case read_port_file() do
      {:ok, port} ->
        if healthy_port?(port) do
          {:ok, %{port: port, reused?: true}}
        else
          find_new_port()
        end

      _ ->
        find_new_port()
    end
  end

  defp select_port(port) when is_integer(port) and port > 0 do
    if port_available?(port) do
      {:ok, %{port: port, reused?: false}}
    else
      {:error, {:port_unavailable, port}}
    end
  end

  defp wait_for_health(port, started_at \\ System.monotonic_time(:millisecond))

  defp wait_for_health(port, started_at) do
    cond do
      healthy_port?(port) ->
        :ok

      System.monotonic_time(:millisecond) - started_at >= @health_timeout_ms ->
        {:error, {:health_timeout, port}}

      true ->
        Process.sleep(@health_poll_ms)
        wait_for_health(port, started_at)
    end
  end

  defp find_new_port do
    with {:ok, port} <- find_open_port(@default_port) do
      {:ok, %{port: port, reused?: false}}
    end
  end

  defp do_find_open_port(_port, 0), do: {:error, :no_open_port}

  defp do_find_open_port(port, remaining) do
    if port_available?(port) do
      {:ok, port}
    else
      do_find_open_port(port + 1, remaining - 1)
    end
  end

  defp port_available?(port) do
    case :gen_tcp.listen(port, [:binary, active: false, ip: {127, 0, 0, 1}]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, :eaddrinuse} ->
        false

      {:error, _reason} ->
        false
    end
  end

  defp browser_command(url) do
    case :os.type() do
      {:unix, :darwin} -> {"open", [url]}
      {:unix, _} -> {"xdg-open", [url]}
      {:win32, _} -> {"cmd", ["/c", "start", url]}
      _ -> nil
    end
  end

  defp parse_port_option("auto"), do: {:ok, :auto}

  defp parse_port_option(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 ->
        {:ok, parsed}

      _ ->
        {:error, "Expected --port to be `auto` or a positive integer, got: #{inspect(value)}"}
    end
  end
end
