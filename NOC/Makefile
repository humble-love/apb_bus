TEST ?= noc_sanity_test

.PHONY: all compile run verdi clean

all: compile

compile:
	bash sim/scripts/compile.sh

run:
	bash sim/scripts/run.sh $(TEST)

verdi:
	bash sim/scripts/verdi.sh

clean:
	rm -rf sim/simv sim/simv.daidir sim/compile.log sim/sim.log
	rm -rf sim/waves/*.fsdb sim/waves/*.vpd
	rm -rf sim/verdiLog sim/novas.conf sim/novas_dump.log sim/novas.rc
	rm -rf sim/AN.DB sim/csrc sim/vc_hdrs.h sim/uvm_dpi.so*
	rm -rf sim/tr_db.log sim/ucli.key sim/vlogan.log
	rm -rf sim/DVEfiles sim/inter.vpd sim/build sim/build2
	rm -f sim/pthread_yield_compat.o
