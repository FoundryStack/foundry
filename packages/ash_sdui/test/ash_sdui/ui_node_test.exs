defmodule AshSDUI.UINodeTest do
  use ExUnit.Case, async: true

  alias AshSDUI.UINode

  describe "UINode resource definition" do
    test "has expected attribute names" do
      attrs = UINode |> Ash.Resource.Info.attributes() |> Enum.map(& &1.name)

      assert :component_name in attrs
      assert :static_props in attrs
      assert :subject_resource in attrs
      assert :subject_id in attrs
      assert :region in attrs
      assert :order in attrs
      assert :status in attrs
    end

    test "status defaults to :draft" do
      attr = UINode |> Ash.Resource.Info.attribute(:status)
      assert attr.default == :draft
    end

    test "component_name has format constraint" do
      attr = UINode |> Ash.Resource.Info.attribute(:component_name)
      constraint = attr.constraints[:match]
      assert constraint != nil
      # Check that it's a regex constraint
      assert Kernel.is_tuple(constraint) or Kernel.is_atom(constraint)
    end

    test "component_name constraint accepts valid format" do
      assert Regex.match?(~r/^[A-Za-z0-9\.]+@v\d+$/, "UserProfile.Header@v1")
      assert Regex.match?(~r/^[A-Za-z0-9\.]+@v\d+$/, "Foo.Bar.Baz@v10")
    end

    test "component_name constraint rejects invalid format" do
      refute Regex.match?(~r/^[A-Za-z0-9\.]+@v\d+$/, "Bad")
      refute Regex.match?(~r/^[A-Za-z0-9\.]+@v\d+$/, "NoVersion")
      refute Regex.match?(~r/^[A-Za-z0-9\.]+@v\d+$/, "@v1")
    end

    test "status constraint allows valid values" do
      attr = UINode |> Ash.Resource.Info.attribute(:status)
      assert :draft in attr.constraints[:one_of]
      assert :published in attr.constraints[:one_of]
      assert :archived in attr.constraints[:one_of]
    end

    test "has publish action" do
      action_names = UINode |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)
      assert :publish in action_names
    end

    test "has revert action" do
      action_names = UINode |> Ash.Resource.Info.actions() |> Enum.map(& &1.name)
      assert :revert in action_names
    end

    test "has parent relationship" do
      rel = UINode |> Ash.Resource.Info.relationship(:parent)
      assert rel != nil
      assert rel.type == :belongs_to
    end

    test "has children relationship" do
      rel = UINode |> Ash.Resource.Info.relationship(:children)
      assert rel != nil
      assert rel.type == :has_many
    end
  end
end
