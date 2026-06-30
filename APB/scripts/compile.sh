#!/bin/bash
# VCS Compile Script for APB Bus Framework
# Compiles all RTL + UVM files with Verdi FSDB support

set -e

# Configuration — adjust to your environment
VCS_HOME=${VCS_HOME:-/home/openclaw/hardware/Synopsys/Install/vcs/O-2018.09-SP2}
VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))

cd $PROJ_ROOT
mkdir -p waves

# Ensure dc (desk calculator) is in PATH — VCS 2018 requires it
if [ -x "$HOME/.local/bin/dc" ]; then
    export PATH="$HOME/.local/bin:$PATH"
fi

# Ensure VCS tools are in PATH
export PATH="$VCS_HOME/bin:$PATH"

# License — adjust to your environment
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}

# Verdi PLI paths
VERDI_PLI="$VERDI_HOME/share/PLI/VCS/LINUX64"

echo "========================================="
echo " VCS Compilation for APB Bus Framework"
echo "========================================="
echo "VCS_HOME  = $VCS_HOME"
echo "VERDI_HOME = $VERDI_HOME"
echo ""

echo "[1/2] Analyzing + Elaborating..."
echo ""

# Build the VCS command string.
# We run inside bwrap to work around /bin/sh -> dash incompatibility
# (VCS 2018 internally calls /bin/sh -f, which dash does not support).
# If /bin/sh is already bash, skip bwrap.
if [ "$(readlink -f /bin/sh)" = "/usr/bin/dash" ]; then
    bwrap --bind / / --dev /dev --bind /bin/bash /usr/bin/dash bash -c "
        export VCS_HOME=\"$VCS_HOME\"
        export VERDI_HOME=\"$VERDI_HOME\"
        export PATH=\"$VCS_HOME/bin:$HOME/.local/bin:\$PATH\"
        vcs \
            -full64 \
            -sverilog \
            -ntb_opts uvm-1.2 \
            +v2k \
            -debug_access+all \
            -kdb \
            -lca \
            -fsdb \
            -P $VERDI_PLI/novas.tab \
            $VERDI_PLI/pli.a \
            +vcs+lic+wait \
            -timescale=1ns/1ps \
            -o simv \
            -l compile.log \
            -f scripts/filelist.f \
            pthread_yield_compat.o
    "
else
    export VCS_HOME
    export PATH="$VCS_HOME/bin:$HOME/.local/bin:$PATH"
    vcs \
        -full64 \
        -sverilog \
        -ntb_opts uvm-1.2 \
        +v2k \
        -debug_access+all \
        -kdb \
        -lca \
        -fsdb \
        -P $VERDI_PLI/novas.tab \
        $VERDI_PLI/pli.a \
        +vcs+lic+wait \
        -timescale=1ns/1ps \
        -o simv \
        -l compile.log \
        -f scripts/filelist.f \
        pthread_yield_compat.o
fi

echo ""
echo "[2/2] Build complete."
echo ""
echo "  simv generated successfully."
echo ""
echo "  Run simulation:  ./scripts/run.sh [TEST_NAME]"
echo "  View waveforms:  ./scripts/verdi.sh"
