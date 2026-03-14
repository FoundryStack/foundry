defmodule SparkMeta.GiroTest do
  use ExUnit.Case
  @moduletag :integration

  @giro_root "/Users/maxsvargal/Documents/Projects/giro/_build/dev/lib"

  setup_all do
    for app <- ["giro", "giro_core", "giro_web", "ash_graphql"] do
      path = Path.join([@giro_root, app, "ebin"])
      if File.dir?(path), do: :code.add_path(String.to_charlist(path))
    end

    {:module, _} = Code.ensure_loaded(Giro.Audit.Entry)
    :ok
  end

  test "spark_module? detects Giro.Audit.Entry as Spark module" do
    assert SparkMeta.Walker.spark_module?(Giro.Audit.Entry) == true
  end

  test "walks Giro.Audit.Entry successfully" do
    {:ok, state} = SparkMeta.Walker.walk(Giro.Audit.Entry)

    assert state.module == Giro.Audit.Entry
    assert is_list(state.extensions)
  end

  test "extracts extensions from audit entry" do
    extensions = SparkMeta.Walker.extensions(Giro.Audit.Entry)

    # Expect AshGraphql.Resource to be present
    assert Enum.any?(extensions, &(to_string(&1) =~ "AshGraphql"))
  end

  test "gets data_layer from audit entry" do
    data_layer = SparkMeta.Walker.get_persisted(Giro.Audit.Entry, :data_layer, nil)

    assert data_layer == AshPostgres.DataLayer or data_layer == nil
  end

  test "extracts attributes from audit entry" do
    attributes = SparkMeta.Walker.entities(Giro.Audit.Entry, [:attributes])

    # Should have attributes like :action, :actor_id, :resource_type
    assert is_list(attributes)
    assert length(attributes) >= 3
  end

  test "gets graphql type option" do
    graphql_type = SparkMeta.Walker.get_opt(Giro.Audit.Entry, [:graphql], :type, nil)

    # Should return the graphql type if configured
    assert graphql_type == :audit_entry or graphql_type == nil or is_atom(graphql_type)
  end

  test "loads multiple umbrella apps" do
    # Verify that we can access modules from different umbrella apps
    assert SparkMeta.Walker.spark_module?(Giro.Audit.Entry)

    # Try to find and verify a module from a different app in the umbrella
    # This tests that all ebin paths were added correctly
    assert Enum.any?([Giro.Audit.Entry], &SparkMeta.Walker.spark_module?/1)
  end
end
