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
	rm -rf simv simv.daidir compile.log sim.log
	rm -rf waves/*.fsdb waves/*.vpd
	rm -rf verdiLog novas.conf novas_dump.log novas.rc
	rm -rf AN.DB csrc vc_hdrs.h uvm_dpi.so*
	rm -rf tr_db.log ucli.key vlogan.log inter.vpd
	rm -rf DVEfiles build build2
	rm -f pthread_yield_compat.o
