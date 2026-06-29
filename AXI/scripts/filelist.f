// RTL files
+incdir+rtl
rtl/axi_master.sv
rtl/axi_crossbar_wr.sv
rtl/axi_crossbar_rd.sv
rtl/axi_addr_decoder.sv
rtl/axi_slave_sram.sv
rtl/axi_slave_dfi.sv
rtl/axi_interconnect.sv
rtl/axi_top.sv

// UVM testbench files
+incdir+tb
tb/axi_if.sv
tb/axi_pkg.sv
tb/axi_master_driver.sv
tb/axi_master_monitor.sv
tb/axi_slave_monitor.sv
tb/axi_master_agent.sv
tb/axi_scoreboard.sv
tb/axi_env.sv
tb/sequence_lib.sv
tb/axi_test.sv
tb/tb_top.sv
