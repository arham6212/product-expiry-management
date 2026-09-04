#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$project_root"
exec python3 -m tools.ansar_catalog.cli run_once "$@"

