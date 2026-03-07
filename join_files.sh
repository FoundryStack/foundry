#!/usr/bin/env bash

# join_files.sh - Recursively join all files from a directory (with optional extension filter) into a single file
#
# Usage:
#   ./join_files.sh <directory> <output_file> [extensions...]
#
# Examples:
#   ./join_files.sh ./src output.txt              # All files
#   ./join_files.sh ./src output.txt .ex .exs     # Only .ex and .exs files
#   ./join_files.sh ./docs output.md .md          # Only .md files

set -e

usage() {
  echo "Usage: $0 <directory> <output_file> [extension1 extension2 ...]"
  echo ""
  echo "  directory    - Directory to search recursively"
  echo "  output_file  - Path for the concatenated output file"
  echo "  extensions   - Optional. Filter by file extensions (e.g. .ex .exs .md)"
  echo "                 If omitted, all files are included."
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

DIR="$1"
OUTPUT="$2"
shift 2
EXTENSIONS=("$@")

if [[ ! -d "$DIR" ]]; then
  echo "Error: Directory '$DIR' does not exist or is not a directory." >&2
  exit 1
fi

# Clear or create output file
: > "$OUTPUT"

list_files() {
  if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
    find "$DIR" -type f
  else
    local list
    list=$(mktemp)
    for ext in "${EXTENSIONS[@]}"; do
      [[ "$ext" != .* ]] && ext=".$ext"
      find "$DIR" -type f -name "*$ext" >> "$list"
    done
    sort -u "$list"
    rm -f "$list"
  fi
}

while IFS= read -r f; do
  echo "--- $f ---" >> "$OUTPUT"
  cat "$f" >> "$OUTPUT"
  echo "" >> "$OUTPUT"
done < <(list_files)

echo "Done. Output written to $OUTPUT"
