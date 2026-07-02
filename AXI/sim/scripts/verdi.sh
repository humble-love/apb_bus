#!/bin/bash
PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJ_ROOT"

verdi -sv -f filelist/rtl.f -f sim/filelist/tb.f -ssf sim/waves/*.fsdb &
