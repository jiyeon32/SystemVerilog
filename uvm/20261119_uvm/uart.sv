`include "uvm_macros.svh"

import uvm_pkg::*;

// ============================================================
// Interface
// ============================================================
interface uart_interface(input clk);
	logic				rst;
	logic				rx;
	logic				rx_done;
	logic	[7:0]	rx_data;
endinterface

// ============================================================
// Transaction
// ============================================================

typedef enum {faster, normal, slower} mode_e;

class uart_item extends uvm_sequence_item;
	rand bit	[7:0] data;
	rand bit	[9:0] interval;
	logic			[7:0]	rx_data;
	bit							rst;
	rand mode_e			mode;

	constraint c_interval {
		interval inside {[0:65]};
	}

	`uvm_object_utils_begin(uart_item)
		`uvm_field_int	(data, UVM_ALL_ON)
		`uvm_field_int	(interval, UVM_ALL_ON)
		`uvm_field_int	(rx_data, UVM_ALL_ON)
		`uvm_field_int	(rst, UVM_ALL_ON)
		`uvm_field_enum	(mode_e, mode, UVM_ALL_ON)
		
	`uvm_object_utils_end

	function new(string name = "uart_item");
		super.new(name);
	endfunction
endclass

// ============================================================
// Sequence
// ============================================================
class uart_seq extends uvm_sequence #(uart_item);
	`uvm_object_utils(uart_seq)
	uart_item seq_item;

	function new(string name = "uart_seq");
		super.new(name);
	endfunction

	task body();
		repeat (1) begin
			seq_item = uart_item::type_id::create("seq_item");
			start_item(seq_item);
			if (!seq_item.randomize() with {mode == normal;}) begin
				`uvm_fatal(get_name(), "randomize failed")
			end
			finish_item(seq_item);
		end
	endtask
endclass

// ============================================================
// Driver
// ============================================================
class base_driver extends uvm_driver #(base_item);
	`uvm_component_utils(base_driver)
	base_item seq_item;
	virtual base_interface base_vif;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db #(virtual base_interface)::get(this, "", "base_vif", base_vif)) begin
			`uvm_fatal(get_name(), "unable to access base interface")
		end
	endfunction

	task run_phase(uvm_phase phase);
		forever begin
			seq_item_port.get_next_item(seq_item);
			seq_item_port.item_done();
		end
	endtask
endclass

// ============================================================
// Monitor
// ============================================================
class base_monitor extends uvm_monitor;
	`uvm_component_utils(base_monitor)
	base_item seq_item;
	virtual base_interface base_vif;
	uvm_analysis_port #(base_item) sender;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db #(virtual base_interface)::get(this, "", "base_vif", base_vif)) begin
			`uvm_fatal(get_name(), "unable to access base interface")
		end
		sender = new("sender", this);
	endfunction

	task run_phase(uvm_phase phase);
		forever begin
			seq_item = base_item::type_id::create("seq_item");
			sender.write(seq_item);
		end
	endtask
endclass

// ============================================================
// Agent
// ============================================================
class base_agent extends uvm_agent;
	`uvm_component_utils(base_agent)

	base_driver                drv;
	base_monitor               mon;
	uvm_sequencer #(base_item) sqr;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		drv = base_driver::type_id::create("drv", this);
		mon = base_monitor::type_id::create("mon", this);
		sqr = uvm_sequencer #(base_item)::type_id::create("sqr", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		drv.seq_item_port.connect(sqr.seq_item_export);
	endfunction
endclass

// ============================================================
// Scoreboard
// ============================================================
class base_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(base_scoreboard)
	uvm_analysis_imp #(base_item, base_scoreboard) receiver;

	int pass_cnt = 0, fail_cnt = 0, total_cnt = 0;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		receiver = new("receiver", this);
	endfunction

	virtual function void write(base_item seq_item);
		total_cnt++;
	endfunction

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info(get_name(), $sformatf("total = %0d, pass = %0d, fail = %0d",
		                                total_cnt, pass_cnt, fail_cnt), UVM_NONE)
	endfunction
endclass

// ============================================================
// Coverage
// ============================================================
class base_coverage extends uvm_subscriber #(base_item);
	`uvm_component_utils(base_coverage)
	base_item seq_item;


	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	virtual function void write(base_item t);
		seq_item = t;
	endfunction

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
	endfunction
endclass

// ============================================================
// Env
// ============================================================
class base_env extends uvm_env;
	`uvm_component_utils(base_env)

	base_agent      agt;
	base_scoreboard scb;
	base_coverage   cov;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		agt = base_agent::type_id::create("agt", this);
		scb = base_scoreboard::type_id::create("scb", this);
		cov = base_coverage::type_id::create("cov", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		agt.mon.sender.connect(scb.receiver);
		agt.mon.sender.connect(cov.analysis_export);
	endfunction
endclass

// ============================================================
// Test
// ============================================================
class base_test extends uvm_test;
	`uvm_component_utils(base_test)
	base_seq seq;
	base_env env;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		env = base_env::type_id::create("env", this);
	endfunction

	task run_phase(uvm_phase phase);
		phase.raise_objection(this);
		seq = base_seq::type_id::create("seq");
		seq.start(env.agt.sqr);
		phase.drop_objection(this);
	endtask

	function void end_of_elaboration_phase(uvm_phase phase);
		uvm_root::get().print_topology();
	endfunction
endclass

// ============================================================
// Top
// ============================================================
module tb_top;
	logic clk = 0;
	base_interface base_if(clk);

	always #5 clk = ~clk;

	initial begin
		$fsdbDumpfile("wave.fsdb");
		$fsdbDumpvars(0);
	end

	initial begin
		uvm_config_db #(virtual base_interface)::set(null, "*", "base_vif", base_if);
		run_test("base_test");
	end
endmodule
