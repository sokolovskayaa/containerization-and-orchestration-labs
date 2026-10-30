#!/usr/bin/env bash
# Prepare an isolated upstream checkout with a read-only CNPG discovery extension.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
lab4_source="${LAB4_KRR_SOURCE:-/private/tmp/lab4-krr-cnpg}"
lab4_venv="${LAB4_KRR_VENV:-/private/tmp/lab4-krr-venv}"
pin="$(cat "$root/krr-cnpg/upstream-commit.txt")"
command -v uv >/dev/null || { echo 'Install uv first: brew install uv' >&2; exit 1; }
if [[ ! -d "$lab4_source/.git" ]]; then
  git clone https://github.com/robusta-dev/krr.git "$lab4_source"
  git -C "$lab4_source" checkout "$pin"
fi
[[ "$(git -C "$lab4_source" rev-parse HEAD)" == "$pin" ]] || { echo 'Unexpected KRR source revision' >&2; exit 1; }
if ! git -C "$lab4_source" apply --reverse --check "$root/krr-cnpg/discovery.patch" 2>/dev/null; then
  git -C "$lab4_source" apply --check "$root/krr-cnpg/discovery.patch"
  git -C "$lab4_source" apply "$root/krr-cnpg/discovery.patch"
fi
uv python install 3.12.8
if [[ ! -x "$lab4_venv/bin/python" ]]; then uv venv --python 3.12.8 "$lab4_venv"; fi
uv pip install --python "$lab4_venv/bin/python" -r "$lab4_source/requirements.txt"
printf 'Run KRR using: %s/bin/python %s/krr.py simple ...\n' "$lab4_venv" "$lab4_source"
