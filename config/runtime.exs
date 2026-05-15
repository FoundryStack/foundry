import Config

# CRITICAL: Check if FOUNDRY_STANDALONE is set - this is set by Tauri's launcher.rs
# In release mode, we can't call Foundry.Studio.mix_task_invoked?, so rely on env var
standalone_mode? = System.get_env("FOUNDRY_STANDALONE", "0") == "1"

server_enabled? =
  config_env() == :dev or System.get_env("PHX_SERVER") in ["true", "1"] or standalone_mode?

runtime_port =
  cond do
    port = System.get_env("PORT") ->
      String.to_integer(port)

    server_enabled? and standalone_mode? ->
      # Standalone mode: always use port 4000 for consistency.
      # The Tauri client expects the server on 4000.
      _ = Foundry.Studio.write_port_file(4000)
      4000

    server_enabled? and not standalone_mode? ->
      case Foundry.Studio.resolve_generic_server_port() do
        {:ok, port} ->
          _ = Foundry.Studio.write_port_file(port)
          port

        {:error, _reason} ->
          4000
      end

    true ->
      4000
  end

# Build endpoint config with explicit settings for all modes
check_origin_list = [
  "http://127.0.0.1:4000",
  "http://localhost:4000",
  "//127.0.0.1:4000",
  "//localhost:4000",
  "http://127.0.0.1",
  "http://localhost",
  "//127.0.0.1",
  "//localhost",
  "tauri://localhost",
  "tauri://localhost:4000"
]

endpoint_config = [
  http: [ip: {127, 0, 0, 1}, port: runtime_port],
  url: [host: "127.0.0.1", port: runtime_port],
  server: server_enabled?,
  check_origin: check_origin_list,
  force_ssl: false
]

config :foundry_web, FoundryWeb.Endpoint, endpoint_config

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  #
  # IMPORTANT: The default must be at least 64 bytes for Plug.Session.COOKIE
  # to accept it. Shorter secrets cause 500 errors on routes that set cookies.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      if standalone_mode? do
        "foundry-standalone-secret-key-base-change-me-if-exposed-0000000000"
      else
        raise """
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """
      end

  config :foundry_web, FoundryWeb.Endpoint,
    secret_key_base: secret_key_base

  config :foundry, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
