#!/bin/bash
# Launch Verdi for Waveform Viewing
# Usage: ./scripts/verdi.sh

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
export PATH="$VERDI_HOME/bin:$PATH"

echo "========================================="
echo " Launching Verdi..."
echo "========================================="

verdi \
    -sv \
    -f scripts/filelist.f \
    -ssf waves/apb.fsdb \
    -nologo \
    &
