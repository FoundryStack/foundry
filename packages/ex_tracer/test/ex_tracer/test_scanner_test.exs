defmodule ExTracer.TestScannerTest do
  use ExUnit.Case, async: true

  alias ExTracer.TestScanner

  defmodule MockTestFramework do
    @behaviour ExTracer.TestFramework

    @impl true
    def block_patterns, do: [{:test, 2}, {:test, 3}]

    @impl true
    def metadata_attrs, do: [:scenario, :tag]

    @impl true
    def test_kinds, do: %{test: :test}
  end

  test "extracts describe metadata and test blocks through framework callbacks" do
    {:ok, ast} =
      Code.string_to_quoted("""
      defmodule Demo.SampleTest do
        describe "payment flow" do
          @scenario category: :compliance, tags: [:critical], compliance_links: ["RG-001"]

          test "captures executable body" do
            Demo.Payments.run(:ok)
          end
        end
      end
      """)

    [%{describe: describe, metadata: metadata, tests: tests}] =
      TestScanner.extract_from_ast(
        ast,
        "Demo.SampleTest",
        "/tmp/sample_test.exs",
        %{},
        __MODULE__.MockTestFramework,
        fn describe_name, body, _source_module, _file_path, _alias_map, metadata_attrs, test_kinds ->
          %{
            describe: describe_name,
            metadata: TestScanner.extract_scenario_metadata(body, metadata_attrs),
            tests: TestScanner.extract_test_blocks(body, test_kinds)
          }
        end
      )

    assert describe == "payment flow"
    assert metadata.category == :compliance
    assert metadata.tags == [:critical]
    assert metadata.compliance_links == ["RG-001"]

    assert [%ExTracer.TestBlock{name: "captures executable body", kind: :test, line: line}] =
             tests

    assert is_integer(line)
  end

  test "generates stable scenario ids" do
    assert TestScanner.generate_scenario_id("Demo.SampleTest", "Webhook processing flow") ==
             "Demo.SampleTest.webhook_processing_flow"
  end
end
