#!/bin/bash
verdi -sv -f filelist/rtl.f -f sim/filelist/tb.f \
  -ssf sim/waves/noc.fsdb -nologo &
