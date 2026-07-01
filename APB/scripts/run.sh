#!/bin/bash
# Run APB Simulation
# Usage: ./scripts/run.sh [TEST_NAME]
# Default: apb_sanity_test

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

TEST=${1:-apb_sanity_test}

# Set up Verdi FSDB dumper library path
VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
export LD_LIBRARY_PATH="$VERDI_HOME/share/PLI/VCS/linux64:$LD_LIBRARY_PATH"

# License — adjust to your environment
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}

echo "========================================="
echo " Running Test: $TEST"
echo "========================================="

./sim/simv \
    +UVM_TESTNAME=$TEST \
    +fsdb+autoflush \
    -l sim/sim.log \
    +vcs+lic+wait

# Move VCS-generated temp files into sim/
[ -f tr_db.log ] && mv tr_db.log sim/tr_db.log 2>/dev/null || true
[ -f ucli.key ] && mv ucli.key sim/ucli.key 2>/dev/null || true
[ -f vc_hdrs.h ] && mv vc_hdrs.h sim/vc_hdrs.h 2>/dev/null || true

echo ""
echo " Simulation complete. Log: sim/sim.log"
echo " Waveform: sim/waves/apb.fsdb"
