#!/bin/bash
set -e

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"

echo "=== AXI DDR5 Framework Compile ==="

vcs -sverilog -ntb_opts uvm-1.2 \
    -timescale=1ns/1ps \
    -debug_access+all -kdb \
    -P $VERDI_HOME/share/PLI/VCS/LINUX64/novas.tab \
    $VERDI_HOME/share/PLI/VCS/LINUX64/pli.a \
    -l compile.log \
    -f scripts/filelist.f

if [ $? -eq 0 ]; then
    echo "=== Compile SUCCESS ==="
else
    echo "=== Compile FAILED ==="
    exit 1
fi
