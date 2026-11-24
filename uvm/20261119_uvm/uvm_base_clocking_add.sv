`include "uvm_macros.svh"

import uvm_pkg::*;

// interface, virtual interface
interface base_interface(input clk);
	logic [7:0] wdata;	// drive		t_wdata
	logic [7:0] rdata;	// monitor rdata
	logic [7:0] addr;		// drive		t_addr
	logic				we;			// drive		if( kind == WRITE) we = 1

	// clocking concep
	clocking drv_cb @(posedge clk);
		default output #1; // delay
		output wdata;
		output addr;
		output we;
	endclocking

	clocking mon_cb @(posedge clk);
		default input #1step;
		input wdata;
		input addr;
		input we;
		input rdata;
	endclocking

	modport drv_mp(clocking drv_cb, input clk);
endinterface

// UVM_Transaction
typedef enum {READ, WRITE} kind_e;
class base_item extends uvm_sequence_item;
	rand bit [7:0]	t_wdata; // wdata data
	rand bit [7:0]	t_addr; // address
	rand kind_e			kind;		// write enable
	logic		 [7:0]	t_rdata; // read data

	constraint c_addr {
		t_addr inside {[0:63]};
	}

	// item registry to uvm_object
	`uvm_object_utils_begin(base_item)
		`uvm_field_int	(t_wdata, UVM_ALL_ON)
		`uvm_field_int	(t_addr, UVM_ALL_ON)
		`uvm_field_enum	(kind_e, kind, UVM_ALL_ON)
	`uvm_object_utils_end

	function new(string name = "base_item");
		super.new(name);
	endfunction

	function void debug_print(string name);
			`uvm_info(name,$sformatf("t_wdata = %d, t_addr = %d, kind = %d, t_rdata = %d",
																			t_wdata,t_addr,kind,t_rdata), UVM_MEDIUM)
	endfunction

endclass

//UVM_Sequence
class base_seq extends uvm_sequence #(base_item);
	`uvm_object_utils(base_seq)
	base_item seq_item;

	function new(string name = "base_seq");
		super.new(name);
	endfunction

	task body();
		repeat(10) begin
			seq_item = base_item::type_id::create("base_seq_item");
		`uvm_info("base_seq","body - 1 start seq_item", UVM_LOW)
			start_item(seq_item);		// to wait until request frome driver/sequencer
			if (!seq_item.randomize()) begin
				`uvm_fatal("base_seq","fail seq_item randomized")
			end
			// dubug seq item
			seq_item.debug_print("base_seq");

			finish_item(seq_item);
		end
	endtask
endclass

// UVM_Component
//  ENV, AGENT, DRIVER, MONITOR, SCOREBOARD, COVERAGE
// parameterize class driver
class base_driver extends uvm_driver #(base_item);
	`uvm_component_utils(base_driver)
	base_item seq_item;
	// virtual interface handle
	virtual base_interface base_vif;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		// virtual finterface get
		if(!uvm_config_db #(virtual base_interface)::get(this,"","base_vif",base_vif)) begin
			`uvm_fatal(get_name(),"unable to access base interface")
		end
		`uvm_info("base_driver","build phase - driver", UVM_LOW)
	endfunction

	task run_phase(uvm_phase phase);
		super.run_phase(phase);
		forever begin
			seq_item_port.get_next_item(seq_item);
			// non-blocking for clocking block
			@(base_vif.drv_cb);
			// to drive to virtual interface
			base_vif.drv_cb.addr	<= seq_item.t_addr;
			base_vif.drv_cb.wdata <= seq_item.t_wdata;
			if(seq_item.kind == WRITE) begin
				base_vif.drv_cb.we <= 1;
			end else begin
				base_vif.drv_cb.we <= 0;
			end
			`uvm_info("base_driver","run_phase - driver", UVM_LOW)
			seq_item.debug_print("base_driver");
			seq_item_port.item_done();
		end
	endtask
endclass

// normal class
class base_monitor  extends uvm_monitor;
	`uvm_component_utils(base_monitor)
	base_item seq_item;
	// virtual interface handle
  virtual base_interface base_vif;
	// TLM port  : analysis port : output_port, implement_port : input_port
	uvm_analysis_port #(base_item) sender;


	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if(!uvm_config_db #(virtual base_interface)::get(this,"","base_vif",base_vif)) begin
			`uvm_fatal(get_name(),"unable to access base interface")
		end
		// create monitor port ( for uvm_analysis_port )
		sender = new("WRITE", this);
		`uvm_info("base_monitor","build phase - monitor", UVM_LOW)
	endfunction

task run_phase(uvm_phase phase);
	super.run_phase(phase);
	forever begin
		//create seq_item
		seq_item = base_item::type_id::create("base_seq_item");

		@(posedge base_vif.clk);
		#1;
		seq_item.t_addr = base_vif.addr;
		seq_item.t_wdata = base_vif.wdata;
		seq_item.t_rdata = base_vif.rdata;

		if(base_vif.we) seq_item.kind = WRITE;
		else						seq_item.kind = READ;
		// send port data to scoreboard
		sender.write(seq_item);
	end
endtask
endclass

class base_agent  extends uvm_agent;
	`uvm_component_utils(base_agent)

	base_driver		drv;
	base_monitor	mon;
	uvm_sequencer #(base_item) base_sqr; // sequenver

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("base_agent","build phase - agent", UVM_LOW)
		drv = base_driver::type_id::create("drv", this); // (name, parent)
		mon = base_monitor::type_id::create("mon", this); // (name, parent)
		// to use uvm_sequencer
		base_sqr = uvm_sequencer#(base_item)::type_id::create("sqr", this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		`uvm_info("base_agent","connect phase - agent", UVM_LOW)
		drv.seq_item_port.connect(base_sqr.seq_item_export);
	endfunction
endclass

// scoreboard
class base_scoreboard extends uvm_scoreboard;
	`uvm_component_utils(base_scoreboard)
	// uvm_analysis implement port, from analysis port
	uvm_analysis_imp #(base_item, base_scoreboard) receiver;

	function new(string name = "base_scb", uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		// create analysis_imp port
		receiver = new("READ",this);
		`uvm_info("base_scoreboard","build phase - scb", UVM_LOW)
	endfunction

	int pass_cnt = 0, fail_cnt = 0, total_cnt = 0;
	logic [7:0] expect_ram[0:255];

	virtual function void write(base_item seq_item);
		// pass / fail
		`uvm_info("base_scoreboard","write() - scb", UVM_LOW)
		total_cnt ++;

		if(seq_item.kind == WRITE) begin
			// WE = 1, write to ram
			expect_ram[seq_item.t_addr] = seq_item.t_wdata;
		end else begin
			if(seq_item.t_rdata !== 8'hxx) begin
			// WE = 0, read from ram
				if(seq_item.t_rdata === expect_ram[seq_item.t_addr])) begin
						pass_cnt++;
						`uvm_info("base_scb","pass !!", UVM_MEDIUM)
						seq_item.debug_print("base_scb");
				end else begin
						fail_cnt++;
						seq_item.debug_print("base_scb");
						`uvm_error("base_scb",$sformatf("expected data = %d",expect_ram[seq_item.t_addr]))
				end
			end else begin
				`uvm_info("base_scb"," rdata x", UVM_MEDIUM)
			end
		end
	endfunction

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("base_scb",$sformatf("******************"), UVM_NONE)
		`uvm_info("base_scb",$sformatf(" total cnt =  %4d", total_cnt), UVM_NONE)
		`uvm_info("base_scb",$sformatf(" pass  cnt =  %4d", pass_cnt), UVM_NONE)
		`uvm_info("base_scb",$sformatf(" fail  cnt =  %4d", fail_cnt), UVM_NONE)
		`uvm_info("base_scb",$sformatf("******************"), UVM_NONE)
	endfunction
endclass

// coverage class
class base_coverage extends uvm_subscriber #(base_item);
	`uvm_component_utils(base_coverage)

	base_item seq_item;

	covergroup base_cg;
		option.per_instance = 1;

		cp_wdata: coverpoint seq_item.t_wdata {
			bins	range_wdata[] = {[0:255]};
		}
		cp_addr: coverpoint seq_item.t_addr {
			bins	range_addr[] = {[0:255]};
		}
		cp_we: coverpoint seq_item.kind {
			bins	write	= {WRITE}; bins	read	= {READ};
		}
		cx_we_addr : cross cp_we, cp_addr;
	endgroup

	function new(string name = "base_cov", uvm_component parent);
		super.new(name, parent);
		base_cg = new();
	endfunction

	virtual function void write(base_item t);
		this.seq_item = t;
		this.base_cg.sample(); // sample, bins ont time hit
	endfunction

	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		`uvm_info("base_cov",$sformatf("**********************"), UVM_NONE)
		`uvm_info("base_cov",$sformatf("** Coverage Report  **"), UVM_NONE)
		`uvm_info("base_cov",$sformatf(" Overal		=  %6.2f		", base_cg.get_coverage()), UVM_NONE)
		`uvm_info("base_cov",$sformatf(" wdata		=  %6.2f		", base_cg.cp_wdata.get_coverage()), UVM_NONE)
		`uvm_info("base_cov",$sformatf(" addr			=  %6.2f		", base_cg.cp_addr.get_coverage()), UVM_NONE)
		`uvm_info("base_cov",$sformatf(" we				=  %6.2f		", base_cg.cp_we.get_coverage()), UVM_NONE)
		`uvm_info("base_cov",$sformatf(" addr/we	=  %6.2f		", base_cg.cx_we_addr.get_coverage()), UVM_NONE)
		`uvm_info("base_cov",$sformatf("**********************"), UVM_NONE)
	endfunction
endclass

class base_env extends uvm_env;
	`uvm_component_utils(base_env)

	base_agent			agt;
	base_scoreboard scb;
	base_coverage		cov;

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("base_env","build phase - env", UVM_LOW)
		agt = base_agent::type_id::create("agt", this);
		scb = base_scoreboard::type_id::create("scb", this);
		cov = base_coverage::type_id::create("cov",this);
	endfunction

	function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
		`uvm_info("base_env","connect phase - env", UVM_LOW)
		// To connect ayanlys_port to analysis_imp
		agt.mon.sender.connect(scb.receiver);
		// To connect ayanlys_port to analysis_export
		agt.mon.sender.connect(cov.analysis_export); // monitor : cller, coverage : callee
	endfunction
endclass

class uvm_test_base extends uvm_test;
	`uvm_component_utils(uvm_test_base)
	base_seq	seq; // sequence
	base_env	env; // environemt

	function new(string name, uvm_component parent);
		super.new(name, parent);
	endfunction

	// configuration phase
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		`uvm_info("uvm_test_base","build phase - test", UVM_LOW)
		seq = base_seq::type_id::create("seq",this);
		env = base_env::type_id::create("env", this);
	endfunction

	// exceute phase
	task run_phase(uvm_phase phase);
		phase.raise_objection(this);
		`uvm_info("uvm_text_base", "hello_uvm", UVM_LOW)
		// sequence -> sequenver
		seq.start(env.agt.base_sqr);
		//#100;
		`uvm_info("uvm_text_base", "**end of uvm test_base**", UVM_LOW)
		phase.drop_objection(this);
		#10;
	endtask

	// display : hireachy structure
	function void end_of_elaboration_phase(uvm_phase phase);
		uvm_factory f = uvm_factory::get();
		uvm_root::get().print_topology();
		f.print();

	endfunction
endclass

module tb_top;
	logic clk = 0;
	base_interface base_if(clk);
	sram dut (
  .clk		(clk),
	.addr		(base_if.addr),
	.we			(base_if.we),
  .wdata	(base_if.wdata),
	.rdata	(base_if.rdata)
);

	always #5 clk = ~clk;

	initial begin
		$fsdbDumpfile("wave.fsdb");
		$fsdbDumpvars(0);

	end

	initial begin
		// registry uvm db
		uvm_config_db #(virtual base_interface)::set(null, "*","base_vif",base_if);
		run_test("uvm_test_base");
		$finish;
	end

endmodule
