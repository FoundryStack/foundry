# Test what Jason produces with Unicode
test_map = %{
  "unicode_char" => "em-dash: —",
  "smart_quote" => "\"hello\"",
  "apostrophe" => "'s",
  "normal" => "normal text"
}

json = Jason.encode!(test_map, pretty: true)
IO.puts("=== JSON Output ===")
IO.puts(json)

IO.puts("\n=== Checking for backslashes ===")
if String.contains?(json, "\\x{") do
  IO.puts("Found \\x{ sequences!")
else
  IO.puts("No \\x{ sequences found")
end

if String.contains?(json, "\\u") do
  IO.puts("Found \\u sequences")
  json |> String.split("\\u") |> Enum.take(3) |> Enum.each(&IO.puts/1)
end
