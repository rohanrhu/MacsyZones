#!/bin/bash
set -euo pipefail

tests_dir="$(cd "$(dirname "$0")" && pwd)"

"$tests_dir/run_state_tests.sh"
"$tests_dir/test_source_invariants.sh"
