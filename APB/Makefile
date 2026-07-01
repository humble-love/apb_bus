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
	rm -rf sim/simv sim/simv.daidir sim/compile.log sim/sim.log
	rm -rf sim/waves/*.fsdb sim/waves/*.vpd sim/csrc sim/vc_hdrs.h
	rm -rf sim/pthread_yield_compat.o
	rm -rf sim/tr_db.log sim/ucli.key sim/vlogan.log
	rm -rf sim/build sim/build2 sim/AN.DB
	rm -rf verdiLog novas.conf novas_dump.log novas.rc
	rm -rf DVEfiles inter.vpd uvm_dpi.so*
