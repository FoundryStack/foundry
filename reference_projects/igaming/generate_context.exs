require Logger
Logger.configure(level: :error)

context = Foundry.Copilot.ContextBuilder.build()
output_path = "/Users/maxsvargal/Documents/Projects/foundry/copilot_context_debug.md"
File.write!(output_path, context)
size_kb = (byte_size(context) / 1024) |> Float.round(1)
IO.puts("✓ Context written to copilot_context_debug.md (#{size_kb} KB)")
