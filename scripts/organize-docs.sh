#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

DOCS_DIR="$HOME/containers/docs"
cd "$DOCS_DIR" || exit 1

echo "🔧 Normalizing documentation structure in: $DOCS_DIR"

# Map of file patterns → target subfolder
declare -A TARGETS=(
  ["day01*"]="00-foundation"
  ["day02*"]="00-foundation"
  ["day03*"]="00-foundation"
  ["day04*"]="10-services"
  ["day05*"]="10-services"
  ["day06*"]="10-services"
  ["day07*"]="10-services"
  ["quadlets*"]="10-services"
  ["progress*"]="20-operations"
  ["quick-reference*"]="20-operations"
  ["readme*"]="20-operations"
  ["revised-learning-plan*"]="20-operations"
  ["storage-layout*"]="20-operations"
  ["security*"]="30-security"
  ["yubikey*"]="30-security"
  ["homelab-diagnose*"]="99-reports"
  ["latest-summary*"]="99-reports"
)

# Convert all filenames to lowercase first
for f in *; do
  if [[ -f "$f" ]]; then
    lower=$(echo "$f" | tr '[:upper:]' '[:lower:]')
    if [[ "$f" != "$lower" ]]; then
      echo "→ Renaming $f → $lower"
      mv -n "$f" "$lower"
    fi
  fi
done

# Move files according to pattern map
for f in *; do
  [[ -f "$f" ]] || continue
  [[ "$f" =~ \.new$ ]] && continue  # skip empty placeholders

  moved=false
  for pattern in "${!TARGETS[@]}"; do
    if [[ "$f" == $pattern* ]]; then
      dest="${TARGETS[$pattern]}"
      mkdir -p "$dest"
      echo "📁 Moving $f → $dest/"
      mv -n "$f" "$dest/" || mv "$f" "$dest/${f%.md}.bak.md"
      moved=true
      break
    fi
  done

  # Unmatched files go to 99-reports
  if [[ $moved == false ]]; then
    echo "⚠️  Unmatched: $f → 99-reports/"
    mkdir -p 99-reports
    mv -n "$f" 99-reports/ || mv "$f" "99-reports/${f%.md}.bak.md"
  fi
done

echo "✅ Documentation organized successfully."
