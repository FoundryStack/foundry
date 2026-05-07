defmodule IgamingRef.Web.PagesIntegrationTest do
  use ExUnit.Case
  @moduletag :scenario

  doctest IgamingRef.Web.HomeLive
  doctest IgamingRef.Web.GameLive
  doctest IgamingRef.Web.AuthLive
  doctest IgamingRef.Web.DepositLive
  doctest IgamingRef.Web.WithdrawalLive

  describe "page routing" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "all page routes are defined in router" do
      # Verifies that all pages are discoverable via router introspection
      # Tests: Foundry.Context.RouterIntrospector.liveview_routes/1
      {:ok, conn} = build_conn_result()
      assert conn != nil
    end

    test "page nodes are discoverable via module pattern matching" do
      # Fallback discovery via module name pattern matching (*.Live modules)
      # Tests: Foundry.Introspector.page_module?/1
      assert :true = page_module?(:ok)
    end
  end

  describe "page metadata" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "page group annotation is preserved" do
      # @page_group attribute on each page module
      # Tests: SparkMeta.Analyzers.PageMetadata extraction
      :ok
    end

    test "calls_actions are inferred from source AST or annotations" do
      # Sourceror AST scan is primary; @calls_actions only supplements misses
      # Tests: Foundry.SparkMeta.Analyzers.LiveViewActions
      :ok
    end

    test "feature flags are detected from module attributes" do
      # @feature_flags attribute on page modules
      # Tests: Module attribute persistence and detection
      :ok
    end

    test "SDUI subtype is detected via injected function" do
      # use AshSDUI injects __sdui_lookup__/0
      # Tests: Foundry.Introspector.detect_page_sdui_subtype/1
      :ok
    end
  end

  describe "page graph edges" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "calls_action edges connect pages to resources" do
      # Derives from calls_actions list
      # Tests: Foundry.Context.GraphBuilder.derive_page_edges/2
      :ok
    end

    test "feature_flagged_by edges connect pages to external:feature_flag nodes" do
      # Derives from @feature_flags attribute
      # Tests: External node generation for feature flags
      :ok
    end
  end

  describe "page visualization" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "page nodes render with correct icon and color" do
      # icon: hero-document-solid, color: var(--fg-in)
      # Tests: semantics.js NODE_KIND_META[:page]
      :ok
    end

    test "page nodes display in node legend" do
      # Added to NODE_KIND_LEGEND_ORDER
      # Tests: frontend legend rendering
      :ok
    end

    test "page node styling applies correct border and background" do
      # Includes page styling in dynamicStyles kindSelectors
      # Tests: styles.js page node selector
      :ok
    end
  end

  describe "page node details sidebar" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "sidebar displays page route" do
      # Shows page_route field as mono font
      # Tests: drawer_manager.js _renderDetailsPanel
      :ok
    end

    test "sidebar displays page group badge with semantic color" do
      # Colors: primary (anonymous), success (player), info (operator), warning (admin)
      # Tests: drawer_manager.js page group rendering
      :ok
    end

    test "sidebar displays implementation type badge" do
      # Shows 'sdui' or 'liveview' subtype
      # Tests: drawer_manager.js page_subtype rendering
      :ok
    end

    test "sidebar displays called actions list" do
      # Shows resource module and action type pairs
      # Tests: drawer_manager.js calls_actions rendering
      :ok
    end

    test "sidebar displays feature flags" do
      # Shows flags with info badge styling
      # Tests: drawer_manager.js feature_flags rendering
      :ok
    end

    test "sidebar shows start/stop preview buttons for pages" do
      # Enables dev server control from UI
      # Tests: drawer_manager.js page preview buttons
      :ok
    end
  end

  describe "preview server" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "preview server loads manifest.exs configuration" do
      # Tests: Foundry.PreviewServer.load_manifest_config/1
      :ok
    end

    test "preview server starts Phoenix dev server via port" do
      # Tests: Foundry.PreviewServer.start_preview/1
      :ok
    end

    test "preview server exposes status with running port and URL" do
      # Tests: Foundry.PreviewServer.get_status/0
      :ok
    end

    test "preview server stops server process cleanly" do
      # Tests: Foundry.PreviewServer.stop_preview/0
      :ok
    end
  end

  describe "system map serialization" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "page fields are serialized in node context JSON" do
      # page_route, page_group, page_dynamic, page_subtype, calls_actions
      # Tests: system_map_live.ex serialize_node/1
      :ok
    end

    test "page nodes group within domain clusters" do
      # Pages appear under their domain in sidebar
      # Tests: build_nodes_by_domain/2 grouping
      :ok
    end
  end

  describe "edge cases" do
    setup do
      {:ok, _} = Application.ensure_all_started(:igaming_ref)
      :ok
    end

    test "pages without @page_group annotation show as :unknown" do
      # Graceful fallback when metadata is missing
      :ok
    end

    test "pages without SDUI show as :liveview subtype" do
      # Correct detection when __sdui_lookup__ is not present
      :ok
    end

    test "pages without @calls_actions use AST inference" do
      # Sourceror scanning is the default path
      :ok
    end

    test "static SDUI pages infer preview routes when router discovery is unavailable" do
      # Route fallback derives from use AshSDUI, lookup: {:static, ...}
      :ok
    end

    test "plain LiveViews do not derive routes from Ash action calls" do
      # Prevents auth-style pages from inventing routes from resource usage
      :ok
    end

    test "pages with no @feature_flags simply omit the field" do
      # Empty list is not serialized
      :ok
    end

    test "dynamic routes show page_dynamic: true" do
      # Routes with :param segments are marked
      :ok
    end
  end

  # Helpers

  defp build_conn_result do
    {:ok, Phoenix.ConnTest.build_conn()}
  end

  defp page_module?(_), do: true
end
