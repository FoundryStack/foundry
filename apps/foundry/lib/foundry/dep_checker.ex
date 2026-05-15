defmodule Foundry.DepChecker do
  @moduledoc """
  Checks system dependencies required for Foundry.
  """

  @deps [:erlang, :elixir, :node, :bun]

  def check_all do
    Map.new(@deps, fn dep -> {dep, check(dep)} end)
  end

  def blocking_missing?(results) do
    not results[:elixir].installed? or
      not (results[:node].installed? or results[:bun].installed?)
  end

  defp check(:erlang) do
    case System.find_executable("erl") do
      nil ->
        %{installed?: false, version: nil, name: "Erlang/OTP", required?: true}

      _erl_path ->
        # Erlang/OTP is running (we're in a Mix project), so it's installed
        version = get_otp_version()
        %{installed?: true, version: version, name: "Erlang/OTP", required?: true}
    end
  end

  defp get_otp_version do
    case System.otp_release() do
      version when is_binary(version) -> "Erlang/OTP #{version}"
      _ -> nil
    end
  end

  defp check(:elixir) do
    case System.find_executable("elixir") do
      nil ->
        %{installed?: false, version: nil, name: "Elixir", required?: true}

      _elixir_path ->
        case System.cmd("elixir", ["--version"], stderr_to_stdout: true) do
          {output, 0} ->
            version = output |> String.split("\n") |> List.first() |> String.trim()
            %{installed?: true, version: version, name: "Elixir", required?: true}

          _ ->
            %{installed?: false, version: nil, name: "Elixir", required?: true}
        end
    end
  end

  defp check(:node) do
    case System.find_executable("node") do
      nil ->
        %{installed?: false, version: nil, name: "Node.js", required?: false}

      _node_path ->
        case System.cmd("node", ["--version"], stderr_to_stdout: true) do
          {output, 0} ->
            version = output |> String.trim()
            %{installed?: true, version: version, name: "Node.js", required?: false}

          _ ->
            %{installed?: false, version: nil, name: "Node.js", required?: false}
        end
    end
  end

  defp check(:bun) do
    case System.find_executable("bun") do
      nil ->
        %{installed?: false, version: nil, name: "Bun", required?: false}

      _bun_path ->
        case System.cmd("bun", ["--version"], stderr_to_stdout: true) do
          {output, 0} ->
            version = output |> String.trim()
            %{installed?: true, version: version, name: "Bun", required?: false}

          _ ->
            %{installed?: false, version: nil, name: "Bun", required?: false}
        end
    end
  end

end
