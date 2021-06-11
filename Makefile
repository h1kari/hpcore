# FPGA variables
SOURCES= src/hoggephase.v src/wb_hp.v

all: test_wb_hp

test_wb_hp:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -s wb_hp_test -g2012 test/wb_hp_test.v src/wb_hp.v src/hoggephase.v
	vvp sim_build/sim.vvp |tee sim_build/sim.log
	! grep -q FAIL sim_build/sim.log

show_%: %.vcd %.gtkw
	gtkwave $^

clean:
	rm -rf *vcd sim_build test/__pycache__

.PHONY: clean
