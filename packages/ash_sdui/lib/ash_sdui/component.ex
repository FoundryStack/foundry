defmodule AshSDUI.Component do
  @moduledoc """
  Macro for declaring an SDUI component.

  ## Usage

      defmodule MyApp.Components.UserProfile.Header do
        use AshSDUI.Component, fragment: \"""
          fragment UserProfileHeaderData on User {
            username
            avatarUrl
          }
        \"""

        def render(assigns) do
          ~H\"""
          <div><%= @subject.username %></div>
          \"""
        end
      end

  The component name is derived from the module alias. `MyApp.Components.UserProfile.Header`
  becomes `"UserProfile.Header@v1"` (drops up to and including `Components`, appends version).
  Set `@version "v2"` before `use AshSDUI.Component` to override the default `v1`.
  """

  defmacro __using__(opts) do
    fragment = Keyword.fetch!(opts, :fragment)

    quote do
      @ash_sdui_fragment unquote(fragment)
      @before_compile AshSDUI.Component
    end
  end

  defmacro __before_compile__(env) do
    fragment = Module.get_attribute(env.module, :ash_sdui_fragment)
    version = Module.get_attribute(env.module, :version) || "v1"

    component_name = derive_component_name(env.module, version)
    subject_types = infer_subject_types(fragment)

    quote do
      def __ash_sdui_component_name__, do: unquote(component_name)
      def __ash_sdui_fragment__, do: unquote(fragment)
      def __ash_sdui_subject_types__, do: unquote(subject_types)

      AshSDUI.Registry.register(
        unquote(component_name),
        __MODULE__,
        %{fragment: unquote(fragment), subject_types: unquote(subject_types)}
      )
    end
  end

  @doc false
  def derive_component_name(module, version) do
    parts = module |> Module.split()

    # Drop everything up to and including "Components" or "Component" boundary
    suffix_parts =
      case Enum.find_index(parts, &(&1 in ["Components", "Component"])) do
        nil ->
          # No boundary found; if we have Test in the name, drop it
          case Enum.find_index(parts, &(&1 == "Test")) do
            nil -> Enum.drop(parts, max(0, length(parts) - 2))
            idx -> Enum.drop(parts, idx + 1)
          end

        idx ->
          Enum.drop(parts, idx + 1)
      end

    name = Enum.join(suffix_parts, ".")
    "#{name}@#{version}"
  end

  @doc false
  def infer_subject_types(fragment) do
    # Parse "on TypeName" patterns from GQL fragment string
    ~r/fragment\s+\w+\s+on\s+(\w+)/
    |> Regex.scan(fragment)
    |> Enum.map(fn [_, type] -> type end)
  end
end
