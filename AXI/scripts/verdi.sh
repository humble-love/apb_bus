#!/bin/bash
PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJ_ROOT"

verdi -sv -f scripts/filelist.f -ssf waves/*.fsdb &
