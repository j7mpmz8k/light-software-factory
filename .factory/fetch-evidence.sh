#!/usr/bin/env bash
# Usage: .factory/fetch-evidence.sh <run_id> <pr_number>
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <run_id> <pr_number>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FACTORY_GH="${SCRIPT_DIR}/bin/gh"

RUN_ID="$1"
PR_NUM="$2"
ARTIFACT_NAME="pr-${PR_NUM}-evidence"
OUT_DIR="/tmp/pr-evidence/pr-${PR_NUM}-run-${RUN_ID}"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

if ! "$FACTORY_GH" run download "$RUN_ID" --name "$ARTIFACT_NAME" --dir "$OUT_DIR" 2>/dev/null; then
  echo "[fetch-evidence] No '${ARTIFACT_NAME}' artifact found on run #${RUN_ID} (non-Playwright or skipped E2E run)."
  exit 0
fi

echo "[fetch-evidence] Downloaded '${ARTIFACT_NAME}' into ${OUT_DIR}"
IMAGES="$(find "$OUT_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) | sort || true)"

if [ -n "$IMAGES" ]; then
  echo "[fetch-evidence] Screenshot files ready for Hermes Vision inspection:"
  printf '%s\n' "$IMAGES"
else
  echo "[fetch-evidence] Artifact extracted (no PNG/JPG screenshots found; inspect HTML/trace reports in ${OUT_DIR})."
fi
