import Config

# Foundry-specific configuration
config :foundry,
  ash_domains: [Foundry.Audit, Foundry.Config, Foundry.Proposals, Foundry.Context, Foundry.Chat]

# Configure the mailer for standalone usage
config :foundry, Foundry.Mailer, adapter: Swoosh.Adapters.Local
