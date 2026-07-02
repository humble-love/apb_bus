#!/bin/bash
# VCS Compile Script for NOC 8×8 Mesh
set -e

VCS_HOME=${VCS_HOME:-/home/openclaw/hardware/Synopsys/Install/vcs/O-2018.09-SP2}
VERDI_HOME=${VERDI_HOME:-/home/openclaw/hardware/Synopsys/Install/verdi/Verdi_O-2018.09-SP2}
PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

cd "$PROJ_ROOT"
mkdir -p waves

# Ensure VCS tools are in PATH
export PATH="$VCS_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$VERDI_HOME/share/PLI/VCS/LINUX64:$LD_LIBRARY_PATH"

# License
export LM_LICENSE_FILE=${LM_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-27000@DESKTOP-T4G2P5D}

# Verdi PLI paths
VERDI_PLI="$VERDI_HOME/share/PLI/VCS/LINUX64"

# Compile pthread_yield compat if needed
if [ ! -f pthread_yield_compat.o ]; then
    gcc -c -fPIC pthread_yield_compat.c -o pthread_yield_compat.o
fi

echo "========================================="
echo " VCS Compilation for NOC 8x8 Mesh"
echo "========================================="

bwrap --bind / / --dev /dev --bind /bin/bash /usr/bin/dash bash -c "
    export VCS_HOME=\"$VCS_HOME\"
    export VERDI_HOME=\"$VERDI_HOME\"
    export PATH=\"$VCS_HOME/bin:\$PATH\"
    export LD_LIBRARY_PATH=\"$VERDI_HOME/share/PLI/VCS/LINUX64:\$LD_LIBRARY_PATH\"
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
        -timescale=1ns/10ps \
        -o simv \
        -l compile.log \
        -f filelist/rtl.f \
        -f sim/filelist/tb.f \
        pthread_yield_compat.o
"

echo ""
echo "  simv generated successfully."
