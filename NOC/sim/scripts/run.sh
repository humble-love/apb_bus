#!/bin/bash
set -e
VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
export LD_LIBRARY_PATH="$VERDI_HOME/share/PLI/VCS/LINUX64:$LD_LIBRARY_PATH"

TEST=${1:-noc_sanity_test}

./sim/simv +UVM_TESTNAME=$TEST \
  +UVM_VERBOSITY=UVM_MEDIUM \
  -l sim/sim.log

# Move VCS-generated temp files into sim/
[ -f tr_db.log ] && mv tr_db.log sim/tr_db.log 2>/dev/null || true
[ -f ucli.key ] && mv ucli.key sim/ucli.key 2>/dev/null || true
