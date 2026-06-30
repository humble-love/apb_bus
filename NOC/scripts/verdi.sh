#!/bin/bash
verdi -sv -f filelist/rtl.f -f filelist/tb.f \
  -ssf waves/noc.fsdb -nologo &
