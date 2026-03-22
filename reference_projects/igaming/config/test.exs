import Config

# Disable Swoosh HTTP client — not needed for Foundry lint/context tasks
config :swoosh, :api_client, false
