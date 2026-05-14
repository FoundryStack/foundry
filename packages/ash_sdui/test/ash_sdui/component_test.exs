defmodule AshSDUI.ComponentTest do
  use ExUnit.Case, async: true

  alias AshSDUI.Component

  describe "derive_component_name/2" do
    test "drops up to Components boundary" do
      assert "UserProfile.Header@v1" ==
               Component.derive_component_name(MyApp.Components.UserProfile.Header, "v1")
    end

    test "handles module without Components boundary — takes last 2 segments" do
      assert "UserProfile.Header@v2" ==
               Component.derive_component_name(UserProfile.Header, "v2")
    end

    test "single segment module uses full name" do
      assert "Header@v1" ==
               Component.derive_component_name(Header, "v1")
    end
  end

  describe "infer_subject_types/1" do
    test "extracts type from fragment" do
      fragment = """
      fragment UserProfileHeaderData on User {
        username
        avatarUrl
      }
      """

      assert ["User"] == Component.infer_subject_types(fragment)
    end

    test "extracts multiple fragment types" do
      fragment = """
      fragment A on User { id }
      fragment B on Player { id }
      """

      assert ["User", "Player"] == Component.infer_subject_types(fragment)
    end

    test "returns empty list for fragment with no on clause" do
      assert [] == Component.infer_subject_types("fragment A { id }")
    end
  end

  describe "use AshSDUI.Component" do
    test "component exposes metadata functions" do
      assert "SampleTestComponent@v1" == AshSDUI.Test.SampleTestComponent.__ash_sdui_component_name__()
      assert ["User"] == AshSDUI.Test.SampleTestComponent.__ash_sdui_subject_types__()
    end
  end
end
