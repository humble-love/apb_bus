#!/bin/bash
set -e

TEST=${1:-axi_sanity_test}
PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJ_ROOT"

mkdir -p waves

echo "=== Running test: $TEST ==="
./simv +UVM_TESTNAME=$TEST +fsdb+autoflush -cm line+cond+tgl -l sim.log

if [ $? -eq 0 ]; then
    echo "=== Simulation PASSED ==="
else
    echo "=== Simulation FAILED ==="
    exit 1
fi
