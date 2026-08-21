#!/usr/bin/env bash
set -euo pipefail

# Renders and validates every infra/* and apps/* module, the same
# directories the ApplicationSets discover (see
# argocd-resources/applicationset-*.yaml). Chart.yaml present -> helm
# dependency update + helm template + helm lint. No Chart.yaml -> the
# directory's *.yaml files are wrapped into a throwaway chart's templates/
# and run through `helm template`, which is enough to catch YAML syntax
# errors without a second parsing tool.
#
# Usage: ./scripts/render.sh   (no arguments)

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v helm >/dev/null 2>&1; then
  echo "error: helm is required but not installed" >&2
  exit 1
fi

tmpdirs=()
cleanup() {
  local d
  for d in "${tmpdirs[@]:-}"; do
    [[ -n "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

failures=()

check_chart() {
  local dir="$1" out
  if ! out=$(helm dependency update "$dir" 2>&1); then
    echo "FAIL  $dir (helm dependency update)"
    echo "$out" | sed 's/^/      /'
    failures+=("$dir"); return
  fi
  if ! out=$(helm template "$dir" -f "$dir/values.yaml" 2>&1); then
    echo "FAIL  $dir (helm template)"
    echo "$out" | sed 's/^/      /'
    failures+=("$dir"); return
  fi
  if ! out=$(helm lint "$dir" 2>&1); then
    echo "FAIL  $dir (helm lint)"
    echo "$out" | sed 's/^/      /'
    failures+=("$dir"); return
  fi
  echo "OK    $dir"
}

check_plain() {
  local dir="$1" out tmp
  tmp="$(mktemp -d)"
  tmpdirs+=("$tmp")
  mkdir -p "$tmp/templates"
  cp "$dir"/*.yaml "$tmp/templates/" 2>/dev/null || true
  cat > "$tmp/Chart.yaml" <<CHART
apiVersion: v2
name: render-check
version: 0.0.0
CHART
  if ! out=$(helm template "$tmp" 2>&1); then
    echo "FAIL  $dir"
    echo "$out" | sed 's/^/      /'
    failures+=("$dir"); return
  fi
  echo "OK    $dir"
}

for dir in infra/*/ apps/*/; do
  [[ -d "$dir" ]] || continue
  dir="${dir%/}"
  if [[ -f "$dir/Chart.yaml" ]]; then
    check_chart "$dir"
  else
    check_plain "$dir"
  fi
done

echo
if (( ${#failures[@]} > 0 )); then
  echo "${#failures[@]} module(s) failed:"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
echo "all modules OK"
