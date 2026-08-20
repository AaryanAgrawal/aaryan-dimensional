#!/usr/bin/env bash
set -euo pipefail

docs_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
css="$docs_dir/review-document.css"
architecture_md="$docs_dir/ARCHITECTURE.md"

render_with_pandoc() {
  pandoc "$docs_dir/DIOS-PRD.md" \
    --standalone \
    --embed-resources \
    --css "$css" \
    --metadata title="DIOS Product Requirements" \
    --output "$docs_dir/DIOS-PRD.html"

  pandoc "$architecture_md" \
    --standalone \
    --embed-resources \
    --css "$css" \
    --metadata title="DIOS Architecture" \
    --output "$docs_dir/ARCHITECTURE.html"
}

if command -v pandoc >/dev/null 2>&1; then
  render_with_pandoc
elif command -v nix >/dev/null 2>&1; then
  export docs_dir css architecture_md
  nix shell nixpkgs#pandoc -c bash -c "$(declare -f render_with_pandoc); render_with_pandoc"
else
  echo "Rendering requires pandoc or nix." >&2
  exit 1
fi

echo "Rendered:"
echo "  $docs_dir/DIOS-PRD.html"
echo "  $docs_dir/ARCHITECTURE.html"
