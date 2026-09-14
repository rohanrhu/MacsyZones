#!/bin/bash
set -euo pipefail

tests_dir="$(cd "$(dirname "$0")" && pwd)"

"$tests_dir/run_all.sh"
"$tests_dir/build_app.sh" Debug
"$tests_dir/build_app.sh" Release

echo 'MacsyZones full validation: PASS'
