#!/bin/bash
# Launch Verdi for Waveform Viewing
# Usage: ./scripts/verdi.sh

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
export PATH="$VERDI_HOME/bin:$PATH"

# License
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}

# Verdi 2018 needs libpng12 on newer Ubuntu (24.04+)
export LD_LIBRARY_PATH="$VERDI_HOME/share/PLI/VCS/linux64:/home/openclaw/hardware/Synopsys/libpng12.so.0:$LD_LIBRARY_PATH"

echo "========================================="
echo " Launching Verdi..."
echo "========================================="

verdi \
    -sv \
    -f scripts/filelist.f \
    -ssf sim/waves/apb.fsdb \
    -nologo \
    &
