defmodule FoundryWeb.EndpointConfigTest do
  use ExUnit.Case

  # Reads runtime.exs in prod env with given system env overrides.
  # We restore the original env after each call so tests don't leak.
  defp read_runtime_config(env_overrides) do
    runtime_exs = Path.join([File.cwd!(), "..", "..", "config", "runtime.exs"])
    secret = String.duplicate("a", 64)

    base_env = %{
      "SECRET_KEY_BASE" => secret,
      "FOUNDRY_STANDALONE" => "0",
      "PHX_SERVER" => "true",
      "PORT" => "4000"
    }

    merged = Map.merge(base_env, env_overrides)

    original =
      for {k, _} <- merged do
        {k, System.get_env(k)}
      end

    try do
      for {k, v} <- merged do
        if v, do: System.put_env(k, v), else: System.delete_env(k)
      end

      config = Config.Reader.read!(runtime_exs, env: :prod)
      get_in(config, [:foundry_web, FoundryWeb.Endpoint])
    after
      for {k, original_v} <- original do
        if original_v, do: System.put_env(k, original_v), else: System.delete_env(k)
      end
    end
  end

  describe "runtime.exs check_origin configuration" do
    test "without PHX_HOST: check_origin is a whitelist (standalone/local mode)" do
      config = read_runtime_config(%{"PHX_HOST" => nil})
      check_origin = Keyword.fetch!(config, :check_origin)

      assert is_list(check_origin),
             "Expected check_origin to be a whitelist list, got: #{inspect(check_origin)}"

      assert "tauri://localhost" in check_origin
      assert "//localhost" in check_origin
    end

    test "without PHX_HOST: url host defaults to 127.0.0.1" do
      config = read_runtime_config(%{"PHX_HOST" => nil})
      url = Keyword.fetch!(config, :url)
      assert url[:host] == "127.0.0.1"
    end

    test "with PHX_HOST set: check_origin is false (cloud/proxy mode)" do
      config = read_runtime_config(%{"PHX_HOST" => "studio.cloud.foundry.definitivespec.org"})
      check_origin = Keyword.fetch!(config, :check_origin)

      assert check_origin == false,
             "Expected check_origin: false in cloud mode so LiveView longpoll works through proxy, got: #{inspect(check_origin)}"
    end

    test "with PHX_HOST set: url uses https scheme and the public host" do
      host = "studio.cloud.foundry.definitivespec.org"
      config = read_runtime_config(%{"PHX_HOST" => host})
      url = Keyword.fetch!(config, :url)

      assert url[:scheme] == "https"
      assert url[:host] == host
      assert url[:port] == 443
    end

    test "with PHX_HOST set: server is enabled" do
      config = read_runtime_config(%{"PHX_HOST" => "studio.cloud.foundry.definitivespec.org"})
      assert Keyword.fetch!(config, :server) == true
    end

    test "standalone mode ignores PHX_HOST (check_origin stays as whitelist)" do
      config = read_runtime_config(%{"FOUNDRY_STANDALONE" => "1", "PHX_HOST" => "some.host.com"})
      check_origin = Keyword.fetch!(config, :check_origin)

      assert is_list(check_origin),
             "Standalone mode must keep check_origin whitelist even when PHX_HOST is set, got: #{inspect(check_origin)}"
    end
  end

  describe "runtime.exs endpoint URL" do
    test "uses PORT env var when set" do
      config = read_runtime_config(%{"PORT" => "4567"})
      http = Keyword.fetch!(config, :http)
      assert http[:port] == 4567
    end
  end
end
