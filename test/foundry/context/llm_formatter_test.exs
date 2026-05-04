defmodule Foundry.Context.LLMFormatterTest do
  use ExUnit.Case, async: false

  setup_all do
    ref_root =
      __DIR__
      |> Path.split()
      |> Enum.take_while(&(&1 != "apps"))
      |> Path.join()
      |> Path.join("reference_projects/igaming")

    test_path = Path.join(ref_root, "_build/test/lib/igaming_ref/ebin")
    dev_path = Path.join(ref_root, "_build/dev/lib/igaming_ref/ebin")

    :code.add_path(String.to_charlist(test_path))
    :code.add_path(String.to_charlist(dev_path))

    {:ok, manifest} = Foundry.Manifest.Parser.read(ref_root)
    {nodes, edges} = Foundry.Context.GraphBuilder.build(ref_root, manifest)
    spec_kit = Foundry.Context.SpecKitIndexBuilder.build(ref_root)
    context = Foundry.Context.ProjectMap.assemble(manifest, nodes, edges, spec_kit)
    prompt = Foundry.Context.LLMFormatter.format(context)

    {:ok, root: ref_root, spec_kit: spec_kit, prompt: prompt}
  end

  test "spec-kit builder extracts compact doc metadata", %{spec_kit: spec_kit} do
    adr =
      spec_kit["adrs"]
      |> Enum.find(&(&1[:id] == "ADR-001"))

    assert adr
    assert adr[:title] == "Double-Entry Ledger for Financial Transactions"
    assert adr[:status] == "Accepted"
    assert is_binary(adr[:summary])
    assert String.length(adr[:summary]) <= 300
  end

  test "formatter renders spec-kit overview and compact doc summaries", %{prompt: prompt} do
    assert prompt =~ "## Spec-Kit"
    assert prompt =~ "### Overview"
    assert prompt =~ "Navigation: Prefer direct node links (`adrs`, `compliance`, `runbook`)"

    assert prompt =~
             "- ADR-001 · accepted · Double-Entry Ledger for Financial Transactions ::"

    assert prompt =~ ~r/\[FI8\] res .*?\n  > /s
    assert prompt =~ ~r/\[PR4\] rxr .*?\n  > /s
  end

  test "context builder keeps spec navigation in the full system map", %{root: root} do
    prompt = Foundry.Copilot.ContextBuilder.build(project_root: root)

    assert prompt =~ "## System Architecture (Full Project Context)"
    assert prompt =~ "## Spec-Kit"
    refute prompt =~ "## Spec-Kit Index"
  end
end
