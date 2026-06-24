# APB Bus Framework Makefile

TEST ?= apb_sanity_test

.PHONY: all compile run verdi clean

all: compile

compile:
	bash scripts/compile.sh

run:
	bash scripts/run.sh $(TEST)

verdi:
	bash scripts/verdi.sh

clean:
	rm -rf simv simv.daidir compile.log sim.log
	rm -rf waves/*.fsdb
	rm -rf verdiLog novas.*
	rm -rf AN.DB csrc vc_hdrs.h uvm_dpi.so*
	rm -rf DVEfiles inter.vpd
