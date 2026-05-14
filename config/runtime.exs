import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

standalone_command? = Foundry.Studio.mix_task_invoked?("foundry.studio")
phoenix_server_command? = Foundry.Studio.mix_task_invoked?("phx.server")

# CRITICAL: Check if FOUNDRY_STANDALONE is set - this is set by Tauri's launcher.rs
standalone_mode? = System.get_env("FOUNDRY_STANDALONE", "0") == "1" or standalone_command?

# Debug log to verify env var is being read
if System.get_env("FOUNDRY_STANDALONE") != nil do
  IO.warn("FOUNDRY_STANDALONE is set to: #{System.get_env("FOUNDRY_STANDALONE")}")
end

server_enabled? =
  System.get_env("PHX_SERVER") in ["true", "1"] or standalone_mode? or phoenix_server_command?

runtime_port =
  cond do
    port = System.get_env("PORT") ->
      String.to_integer(port)

    server_enabled? and standalone_mode? ->
      # Standalone mode: always use port 4000 for consistency.
      # The Tauri client expects the server on 4000.
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

endpoint_config =
  if standalone_mode? do
    [
      http: [ip: {127, 0, 0, 1}, port: runtime_port],
      url: [host: "127.0.0.1", port: runtime_port],
      server: server_enabled?,
      check_origin: false,
      force_ssl: false
    ]
  else
    [
      http: [ip: {127, 0, 0, 1}, port: runtime_port],
      url: [host: "127.0.0.1", port: runtime_port],
      server: server_enabled?,
      check_origin: check_origin_list
    ]
  end

IO.warn("=" <> String.duplicate("=", 78))
IO.warn("ENDPOINT CONFIG (runtime.exs)")
IO.warn("  standalone_mode?: #{standalone_mode?}")
IO.warn("  server_enabled?: #{server_enabled?}")
IO.warn("  runtime_port: #{runtime_port}")
IO.warn("  check_origin: #{if standalone_mode?, do: "false", else: "explicit list"}")
IO.warn("  url: [host: \"127.0.0.1\", port: #{runtime_port}]")
IO.warn("=" <> String.duplicate("=", 78))

config :foundry_web, FoundryWeb.Endpoint, endpoint_config

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      if standalone_mode? do
        "foundry-standalone-secret-key-base-change-me-if-exposed"
      else
        raise """
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """
      end

  config :foundry_web, FoundryWeb.Endpoint,
    secret_key_base: secret_key_base

  # ## Using releases
  #
  # If you are doing OTP releases, you need to instruct Phoenix
  # to start each relevant endpoint:
  #
  #     config :foundry_web, FoundryWeb.Endpoint, server: true
  #
  # Then you can assemble a release by calling `mix release`.
  # See `mix help release` for more information.

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :foundry_web, FoundryWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :foundry_web, FoundryWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :foundry, Foundry.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.

  config :foundry, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
