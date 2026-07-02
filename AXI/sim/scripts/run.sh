#!/bin/bash
set -e

TEST=${1:-axi_sanity_test}
PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJ_ROOT"
mkdir -p sim/waves

echo "=== Running test: $TEST ==="
./sim/simv +UVM_TESTNAME=$TEST +fsdb+autoflush -cm line+cond+tgl -l sim/sim.log

# Move VCS-generated temp files into sim/
[ -f tr_db.log ] && mv tr_db.log sim/tr_db.log 2>/dev/null || true
[ -f ucli.key ] && mv ucli.key sim/ucli.key 2>/dev/null || true

if [ $? -eq 0 ]; then
    echo "=== Simulation PASSED ==="
else
    echo "=== Simulation FAILED ==="
    exit 1
fi
