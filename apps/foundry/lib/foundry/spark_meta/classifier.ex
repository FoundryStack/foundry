defmodule Foundry.SparkMeta.Classifier do
  @moduledoc false

  @behaviour SparkMeta.Analyzer

  alias SparkMeta.Analysis

  @impl SparkMeta.Analyzer
  def analyze(context, %Analysis{} = analysis) do
    type =
      cond do
        reactor_module?(context.module) and transfer_module?(analysis) -> :transfer
        reactor_module?(context.module) -> :reactor
        oban_worker?(context.module) -> :job
        trigger_module?(context.module) -> :trigger
        blueprint_module?(context.module) -> :blueprint
        provider_module?(context.module) -> :adapter
        liveview_module?(context.module) -> :page
        liveresource_module?(context.module) -> :liveresource
        agent_module?(context.module) -> :agent
        rule_module?(context.module) -> :rule
        ash_resource?(context.module, analysis) -> :resource
        true -> :resource
      end

    attrs = safe_attributes(context.module)
    extensions = Map.get(analysis.facts, :extensions, [])

    foundry =
      %{
        type: type,
        trigger_kind: if(type == :trigger, do: detect_trigger_kind(context.module), else: nil),
        paper_trail: Enum.any?(extensions, &(to_string(&1) == "Elixir.AshPaperTrail.Resource")),
        archival: Enum.any?(extensions, &(to_string(&1) == "Elixir.AshArchival.Resource")),
        authentication_subject: authentication_subject?(context.module, extensions),
        rate_limited: Enum.any?(extensions, &rate_limit_ext?/1),
        oban_queues: extract_oban_queues(context.module, attrs),
        performs: extract_performs(context.module, attrs),
        last_modified: extract_last_modified(context.module)
      }

    {:ok, Analysis.put_fact(analysis, :foundry_classifier, foundry)}
  end

  defp safe_attributes(module) do
    module.__info__(:attributes)
  rescue
    _ -> []
  end

  defp ash_resource?(module, analysis) do
    Map.get(analysis.facts, :ash_resource, %{})[:attributes] != [] ||
      function_exported?(module, :__ash_resource__, 0)
  rescue
    _ -> false
  end

  defp reactor_module?(module) do
    function_exported?(module, :__reactor__, 0) or function_exported?(module, :reactor, 0)
  rescue
    _ -> false
  end

  defp transfer_module?(analysis) do
    Map.get(analysis.facts, :extensions, [])
    |> Enum.any?(&(to_string(&1) == "Elixir.AshDoubleEntry.Transfers.Transfer"))
  end

  defp trigger_module?(module) do
    module_str = Foundry.SparkMeta.Helpers.format_module_fqn(module)

    String.ends_with?(module_str || "", "Webhook") or
      function_exported?(module, :handle_webhook, 3)
  rescue
    _ -> false
  end

  defp detect_trigger_kind(module) do
    module_str = Foundry.SparkMeta.Helpers.format_module_fqn(module)

    cond do
      String.ends_with?(module_str || "", "Webhook") -> "webhook"
      function_exported?(module, :handle_webhook, 3) -> "webhook"
      true -> nil
    end
  rescue
    _ -> nil
  end

  defp oban_worker?(module) do
    function_exported?(module, :__oban_opts__, 0) or
      Oban.Worker in (safe_attributes(module)[:behaviour] || [])
  rescue
    _ -> false
  end

  defp rule_module?(module) do
    module.__info__(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.any?(fn behaviour ->
      behaviour in [Ash.Policy.Check, Ash.Policy.SimpleCheck] or
        (is_atom(behaviour) and String.ends_with?(Atom.to_string(behaviour), ".Rule"))
    end)
  rescue
    _ -> false
  end

  defp blueprint_module?(module), do: function_exported?(module, :__blueprint__, 0)

  defp provider_module?(module) do
    module.__info__(:attributes)
    |> Keyword.get(:behaviour, [])
    |> Enum.any?(fn behaviour ->
      behaviour_str = to_string(behaviour)
      String.contains?(behaviour_str, ["ProviderAdapter", "Provider"])
    end)
  rescue
    _ -> false
  end

  defp liveview_module?(module) do
    Phoenix.LiveView in (module.__info__(:attributes) |> Keyword.get(:behaviour, []))
  rescue
    _ -> false
  end

  defp liveresource_module?(module) do
    module |> to_string() |> String.contains?("Live")
  rescue
    _ -> false
  end

  defp agent_module?(module) do
    attrs = module.__info__(:attributes)
    Keyword.has_key?(attrs, :agent_type)
  rescue
    _ -> false
  end

  defp authentication_ext?(ext) do
    ext in [AshAuthentication, AshAuthentication.Resource] or
      String.contains?(to_string(ext), "AshAuthentication")
  rescue
    _ -> false
  end

  defp authentication_subject?(module, extensions) do
    Enum.any?(extensions, &authentication_ext?/1) and
      SparkMeta.spark_module?(module) and
      SparkMeta.entities(module, [:authentication, :strategies]) != []
  rescue
    _ -> false
  end

  defp rate_limit_ext?(_ext), do: false

  defp extract_oban_queues(module, attrs) do
    if function_exported?(module, :__oban_opts__, 0) do
      case module.__oban_opts__() |> Keyword.get(:queue) do
        nil -> []
        queue -> [to_string(queue)]
      end
    else
      if Oban.Worker in Keyword.get(attrs, :behaviour, []) do
        extract_oban_queue_from_source(module)
      else
        []
      end
    end
  rescue
    _ -> []
  end

  defp extract_oban_queue_from_source(module) do
    with path when is_binary(path) <- Foundry.SparkMeta.Helpers.module_source_path(module),
         {:ok, source} <- File.read(path),
         [_, queue] <- Regex.run(~r/use\s+Oban\.Worker,\s*queue:\s*:(\w+)/, source) do
      [queue]
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp extract_performs(_module, attrs) do
    if Keyword.has_key?(attrs, :performs) or Keyword.has_key?(attrs, :foundry) do
      direct = Foundry.SparkMeta.Helpers.get_attr_raw(attrs, :performs)

      from_foundry =
        with cfg when is_map(cfg) <- Foundry.SparkMeta.Helpers.get_attr_raw(attrs, :foundry),
             value when not is_nil(value) <- Map.get(cfg, :performs) do
          value
        else
          _ -> nil
        end

      case direct || from_foundry do
        value when is_atom(value) -> Foundry.SparkMeta.Helpers.format_module_fqn(value)
        value when is_binary(value) -> value
        _ -> nil
      end
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp extract_last_modified(module) do
    module |> :code.which() |> to_string() |> File.stat!() |> then(& &1.mtime)
  rescue
    _ -> nil
  end
end
