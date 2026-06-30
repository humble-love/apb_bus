#!/bin/bash
set -e
TEST=${1:-noc_sanity_test}

./simv +UVM_TESTNAME=$TEST \
  +UVM_VERBOSITY=UVM_MEDIUM \
  -l sim.log
