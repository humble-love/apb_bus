#!/bin/bash
# Run APB Simulation
# Usage: ./scripts/run.sh [TEST_NAME]
# Default: apb_sanity_test

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

TEST=${1:-apb_sanity_test}

echo "========================================="
echo " Running Test: $TEST"
echo "========================================="

./simv \
    +UVM_TESTNAME=$TEST \
    +fsdb+autoflush \
    -l sim.log \
    +vcs+lic+wait

echo ""
echo " Simulation complete. Log: sim.log"
echo " Waveform: waves/apb.fsdb"
