#!/bin/bash
# VCS Compile Script for APB Bus Framework
# Compiles all RTL + UVM files with Verdi FSDB support

set -e

# Configuration — adjust to your environment
VCS_HOME=${VCS_HOME:-/opt/synopsys/vcs}
VERDI_HOME=${VERDI_HOME:-/opt/synopsys/verdi}
PROJ_ROOT=$(dirname $(dirname $(readlink -f $0)))

cd $PROJ_ROOT
mkdir -p waves

echo "========================================="
echo " VCS Compilation for APB Bus Framework"
echo "========================================="

echo "[1/2] Analyzing + Elaborating..."
vcs \
    -full64 \
    -sverilog \
    -ntb_opts uvm-1.2 \
    +v2k \
    -debug_access+all \
    -kdb \
    -lca \
    -fsdb \
    -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
    $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a \
    +vcs+lic+wait \
    -timescale=1ns/1ps \
    -o simv \
    -l compile.log \
    -f scripts/filelist.f

echo "[2/2] Build complete."
echo ""
echo "  simv generated successfully."
echo ""
echo "  Run simulation:  ./scripts/run.sh [TEST_NAME]"
echo "  View waveforms:  ./scripts/verdi.sh"
