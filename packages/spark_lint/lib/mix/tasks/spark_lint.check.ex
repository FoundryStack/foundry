defmodule Mix.Tasks.SparkLint.Check do
  @shortdoc "Validate that spark_lint rules are configured (no-op standalone)"

  @moduledoc """
  When run inside a project that has configured SparkLint rules, this task
  provides a standard entry point for running them.

  ## Standalone usage (no rules configured)

      mix spark_lint.check

  Prints a help message explaining how to configure rules.

  ## Usage by rule packages

  Rule packages can depend on `spark_lint` and invoke this task after
  configuring rules via application config:

      # config/config.exs in a project using spark_lint
      config :spark_lint, :rules, [MyApp.LintRules.SomeRule]
      config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0

  ## Exit codes

    - `0` — no `:error` violations
    - `1` — one or more `:error` violations
    - `2` — runner crashed
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    rules = Application.get_env(:spark_lint, :rules, [])
    modules_fn = Application.get_env(:spark_lint, :modules_fn, fn -> [] end)

    if rules == [] do
      Mix.shell().info("""
      spark_lint: no rules configured.

      To use spark_lint.check, add to your config/config.exs:

          config :spark_lint, :rules, [MyApp.LintRules.MyRule]
          config :spark_lint, :modules_fn, &MyApp.Discovery.all_modules/0

      Rules must implement the SparkLint.Rule behaviour.
      """)
    else
      modules = modules_fn.()
      format = parse_format(args)

      {violations, _errors} = SparkLint.run(rules, modules)

      error_count = Enum.count(violations, &(&1.severity == :error))
      warning_count = Enum.count(violations, &(&1.severity == :warning))

      case format do
        :text -> print_text(violations, error_count, warning_count)
        :json -> print_json(violations, error_count, warning_count)
      end

      if error_count > 0 do
        exit({:shutdown, 1})
      end
    end
  rescue
    e ->
      Mix.shell().error("spark_lint.check crashed: #{inspect(e)}")
      exit({:shutdown, 2})
  end

  defp parse_format(args) do
    if "--json" in args or "--format=json" in args, do: :json, else: :text
  end

  defp print_text(violations, error_count, warning_count) do
    Enum.each(violations, fn v ->
      icon =
        case v.severity do
          :error -> "ERROR"
          :warning -> "WARN"
          :info -> "INFO"
        end

      Mix.shell().info("[#{icon}] [#{v.rule}] #{inspect(v.module)}: #{v.message}")
    end)

    Mix.shell().info("\n#{error_count} error(s), #{warning_count} warning(s).")
  end

  defp print_json(violations, error_count, _warning_count) do
    output = %{
      passed: error_count == 0,
      violations:
        Enum.map(violations, fn v ->
          %{rule: v.rule, module: inspect(v.module), severity: v.severity, message: v.message}
        end)
    }

    # Use OTP 27+ :json stdlib for zero deps
    case :json.encode(output) do
      {:ok, json} -> IO.puts(json)
      {:error, _reason} -> IO.write(inspect(output))
    end
  end
end
