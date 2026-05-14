defmodule Foundry.Annotations do
  @moduledoc """
  Registers standard Foundry annotation module attributes as persistent.

  Modules that declare Foundry-specific annotations must `use Foundry.Annotations`
  BEFORE any other `use` macros. This suppresses Elixir compiler warnings about
  "module attribute was set but never used" while keeping attributes accessible
  at runtime via `module.__info__(:attributes)` for the Foundry rules engine.

  Registered attributes:
    - @compliance         - List of regulatory requirement IDs (e.g. [:RG_MGA_005])
    - @telemetry_prefix   - Structured telemetry prefix list
    - @adapter_name       - String identifier for adapter modules
    - @foundry            - Map of Foundry metadata for Oban workers and others
    - @runbook            - Path to operational runbook document
    - @adrs               - List of ADR references
    - @idempotency_key    - Reactor idempotency key for deduplication (atom or tuple)
    - @spec_invariants    - Custom spec rule invariants and constraints
    - @step_side_effects  - Map of step names to lists of side effect declarations

  Usage:
      use Foundry.Annotations

      @compliance [:RG_MGA_005, :RG_UK_011]
      @telemetry_prefix [:igaming_ref, :promotions, :bonus_campaign]

      use Ash.Resource, domain: MyApp.Domain, ...
  """

  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :compliance, persist: true)
      Module.register_attribute(__MODULE__, :telemetry_prefix, persist: true)
      Module.register_attribute(__MODULE__, :adapter_name, persist: true)
      Module.register_attribute(__MODULE__, :foundry, persist: true)
      Module.register_attribute(__MODULE__, :performs, persist: true)
      Module.register_attribute(__MODULE__, :runbook, persist: true)
      Module.register_attribute(__MODULE__, :adrs, persist: true)
      Module.register_attribute(__MODULE__, :idempotency_key, persist: true)
      Module.register_attribute(__MODULE__, :spec_invariants, persist: true)
      Module.register_attribute(__MODULE__, :step_side_effects, persist: true)
    end
  end
end
