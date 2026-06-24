#!/bin/bash
# Launch Verdi for Waveform Viewing
# Usage: ./scripts/verdi.sh

set -e

PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))
cd $PROJ_ROOT

echo "========================================="
echo " Launching Verdi..."
echo "========================================="

verdi \
    -sv \
    -f scripts/filelist.f \
    -ssf waves/apb.fsdb \
    -nologo \
    &
