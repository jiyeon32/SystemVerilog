`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;

package uart_rx_pkg;
    typedef enum bit [1:0] {
        FASTER,
        NORMAL,
        SLOWER
    } kind_e;

    parameter BAUD_CLK = (100_000_000 / 9600);  // 10416
    parameter BAUD_PERIOD = (BAUD_CLK) * 10;
    parameter BAUD_FASTER = BAUD_PERIOD - (BAUD_PERIOD/20); // 5% fast frame per bit
    parameter BAUD_SLOWER = BAUD_PERIOD + (BAUD_PERIOD/20); // 5% slower farme per bit

endpackage


import uart_rx_pkg::*;
// uart interface decleation 
interface uart_interface (
    input clk
);
    logic       rst;
    logic       rx;  // from PC
    logic       rx_done;
    logic [7:0] rx_data;
endinterface


// uart seq item
class uart_seq_item extends uvm_sequence_item;

    rand bit [7:0] send_data;  // range 0~255
    rand bit [9:0] interval;  // range 0~651 clk, unit 10clk
    kind_e         kind;  // uart frame baudrate mode.
    bit            rst;  // dut reset, active positive reset
    logic          rx_done;  // uart receive done, 1tick signal
    logic    [7:0] rx_data;  // uart receive data, sync with rx_done

    `uvm_object_utils_begin(uart_seq_item)
        `uvm_field_int(send_data, UVM_ALL_ON)
        `uvm_field_int(interval, UVM_ALL_ON)
        `uvm_field_enum(kind_e, kind, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "uart_seq_item");
        super.new(name);
    endfunction

    function void debug_print(string name);
        `uvm_info(name, $sformatf(
                  "send_data = %d, interval = %d, kind = %d,rst = %d, rx_done = %d, rx_data = %d",
                  send_data,
                  interval,
                  kind,
                  rst,
                  rx_done,
                  rx_data
                  ), UVM_MEDIUM)
    endfunction

endclass


// sequence 
class uart_rx_sequence extends uvm_sequence #(uart_seq_item);
    `uvm_object_utils(uart_rx_sequence)
    uart_seq_item seq_item;

    int run_count = 2;
    function new(string name = "uart_rx_seq");
        super.new(name);
    endfunction

    task body();
        `uvm_info("SEQ", " body !", UVM_LOW)
        seq_item = uart_seq_item::type_id::create("uart_seq_item");
        repeat (run_count) begin
            start_item(seq_item);  // request to wait until calling from driver
            if (!seq_item.randomize()) begin
                `uvm_fatal("SEQ", " fail seq_item randomized ")
            end
            seq_item.debug_print("SEQ");
            finish_item(seq_item);
        end
    endtask

endclass

// uart driver
class uart_rx_driver extends uvm_driver #(uart_seq_item);
    // factory registry
    `uvm_component_utils(uart_rx_driver)
    // virtual interface handle 
    virtual uart_interface uart_vif;
    uart_seq_item seq_item;
    function new(string name = "uart_rx_drv", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("DRV", " build phase !", UVM_LOW)
        // To get virtual interface from uvm_config_db
        if (!(uvm_config_db#(virtual uart_interface)::get(
                this, "", "uart_vif", uart_vif
            ))) begin
            `uvm_fatal(" uart_rx_driver",
                       "uvm fatal error can't access uart_interface ")
        end
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        // To reset dut
        uart_vif.rst = 1;
        uart_vif.rx  = 1;
        @(negedge uart_vif.clk);
        @(negedge uart_vif.clk);
        uart_vif.rst = 0;

        // operating dut
        forever begin
            // to request to sequence for next seq_item
            seq_item_port.get_next_item(seq_item);
            //drive.
            @(negedge uart_vif.clk);
            uart_vif.rst = 0;
            // call uart_sender task       
            // baud kind normal test
            uart_sender(seq_item.send_data, NORMAL);
            for (int i = 0; i < seq_item.interval; i++) begin
                #10;
            end
            seq_item_port.item_done();
        end
    endtask

    // arg : send_data, baud rate mode : kind  FASTER , NORMAL, SLOWER
    task uart_sender(bit [7:0] send_data, kind_e kind);
        // rx start
        uart_vif.rx = 0;
        if (kind == NORMAL) #(BAUD_PERIOD);
        else if (kind == FASTER) #(BAUD_FASTER);
        else if (kind == SLOWER) #(BAUD_SLOWER);
        // rx data tranceive
        for (int i = 0; i < 8; i++) begin
            uart_vif.rx = send_data[i];
            if (kind == NORMAL) #(BAUD_PERIOD);
            else if (kind == FASTER) #(BAUD_FASTER);
            else if (kind == SLOWER) #(BAUD_SLOWER);
        end
        uart_vif.rx = 1;
        if (kind == NORMAL) #(BAUD_PERIOD);
        else if (kind == FASTER) #(BAUD_FASTER);
        else if (kind == SLOWER) #(BAUD_SLOWER);
    endtask
endclass

`uvm_analysis_imp_decl(_in)
`uvm_analysis_imp_decl(_out)
class uart_rx_monitor_in extends uvm_monitor;
    // factory registy
    `uvm_component_utils(uart_rx_monitor_in)
    // analysis port 
    uvm_analysis_port #(uart_seq_item) in_port;

    // virtual interface handle 
    virtual uart_interface uart_vif;
    uart_seq_item seq_item;

    function new(string name = "uart_rx_mon_in", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("MON_IN", " build phase !", UVM_LOW)
        // To get virtual interface from uvm_config_db
        if (!(uvm_config_db#(virtual uart_interface)::get(
                this, "", "uart_vif", uart_vif
            ))) begin
            `uvm_fatal("MON_IN", "uvm fatal error can't access uart_interface ")
        end
        in_port = new("in_port", this);
    endfunction

    // mon_in run task
    // 1. to collect rx data
    // 2. to calculate uart frame period
    // 3. to excute scb, cov write_in(seq_item) 
    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("MON_IN", " run phase !", UVM_LOW)
        seq_item = uart_seq_item::type_id::create("seq_mon_in");
        forever begin
            // start check rx == 0 
            wait (!uart_vif.rx);  // wait until rx 0, @: edge 1->0
            uart_rx_collector(seq_item.send_data);
            seq_item.interval = 0;  // test
            seq_item.rst      = uart_vif.rst;
            seq_item.kind     = NORMAL;
            in_port.write(seq_item);  // -> analysis_imp_in, write_in()
        end
    endtask

    // uart_rx_collector : to collect rx data    
    task uart_rx_collector(output bit [7:0] expect_send_data);
        #(BAUD_PERIOD / 2);
        for (int i = 0; i < 8; i++) begin
            #(BAUD_PERIOD);
            expect_send_data[i] = uart_vif.rx;
        end
        #(BAUD_PERIOD);
    endtask
endclass

class uart_rx_monitor_out extends uvm_monitor;
    // factory registy
    `uvm_component_utils(uart_rx_monitor_out)
    // virtual interface handle 
    virtual uart_interface uart_vif;
    // analysis port 
    uvm_analysis_port #(uart_seq_item) out_port;
    // seq_item
    uart_seq_item seq_item;
    function new(string name = "uart_rx_mon_out", uvm_component parent);
        super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("MON_OUT", " build phase !", UVM_LOW)
        // To get virtual interface from uvm_config_db
        if (!(uvm_config_db#(virtual uart_interface)::get(
                this, "", "uart_vif", uart_vif
            ))) begin
            `uvm_fatal("MON_OUT",
                       "uvm fatal error can't access uart_interface ")
        end
        out_port = new("out_port", this);
    endfunction
    // mon_in run task
    // 1. to wait rx_done "1" -> rx_data read -> excute scb write 
    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("MON_OUT", " run phase !", UVM_LOW)
        seq_item = uart_seq_item::type_id::create("seq_mon_out");
        forever begin
            // start check rx == 0 
            @ (uart_vif.rx_done);
            seq_item.rx_done  = uart_vif.rx_done;
            seq_item.rx_data  = uart_vif.rx_data;
            seq_item.interval = 0;  // test
            seq_item.rst      = uart_vif.rst;
            seq_item.kind     = NORMAL;
            out_port.write(seq_item);  // -> analysis_imp_out, scb write_out()
        end
    endtask
endclass

// uart rx in agent
class uart_agent_in extends uvm_agent;
    // factory registy
    `uvm_component_utils(uart_agent_in)
    uart_rx_driver                 drv;
    uart_rx_monitor_in             mon_in;
    uvm_sequencer #(uart_seq_item) sqr;

    function new(string name = "uart_agt_in", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("AGT_IN", " build phase !", UVM_LOW)
        drv    = uart_rx_driver::type_id::create("drv", this);
        mon_in = uart_rx_monitor_in::type_id::create("mon_in", this);
        sqr    = uvm_sequencer#(uart_seq_item)::type_id::create("sqr", this);
    endfunction

    // TLM 1.0 connect : sequencer -> driver
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("AGT_IN", " connect phase !", UVM_LOW)
        // uvm_sequencer sqr seq_item_export -> driver seq_item_port
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

// uart rx out agent
class uart_agent_out extends uvm_agent;
    // factory registy
    `uvm_component_utils(uart_agent_out)
    uart_rx_monitor_out mon_out;

    function new(string name = "uart_agt_out", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("AGT_OUT", " build phase !", UVM_LOW)
        mon_out = uart_rx_monitor_out::type_id::create("mon_out", this);
    endfunction
endclass

class uart_rx_scoreboard extends uvm_scoreboard;
    // factory registy
    `uvm_component_utils(uart_rx_scoreboard)
    // uvm analysis_imp in port
    uvm_analysis_imp_in #(uart_seq_item, uart_rx_scoreboard) imp_in;  // imp_in -> write_in : mon_in->write()
    // uvm analysis_imp out port
    uvm_analysis_imp_out #(uart_seq_item, uart_rx_scoreboard) imp_out;  // imp_out -> write_out : mon_out->write()

    function new(string name = "uart_rx_scb", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("SCB", " build phase !", UVM_LOW)
        imp_in = new("imp_in", this);
        imp_out = new("imp_out", this);
    endfunction

    logic [7:0] expect_data = 0;
    int pass_cnt = 0, fail_cnt = 0, total_cnt = 0;
    function void write_in(uart_seq_item t);
        // store expect data for pass/fail
        expect_data = t.send_data;
        t.debug_print("SCB");
    endfunction
    function void write_out(uart_seq_item t);
        total_cnt++;
        // pass/fail 
        if (expect_data == t.rx_data) begin
            pass_cnt++;
        end else begin
            fail_cnt++;
        end
        t.debug_print("SCB");
    endfunction
endclass

class uart_rx_environment extends uvm_env;
    // factory registy
    `uvm_component_utils(uart_rx_environment)
    uart_agent_in      agt_in;
    uart_agent_out     agt_out;
    uart_rx_scoreboard scb;
    function new(string name = "uart_rx_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        `uvm_info("ENV", " build phase !", UVM_LOW)
        agt_in  = uart_agent_in::type_id::create("agt_in", this);
        agt_out = uart_agent_out::type_id::create("agt_out", this);
        scb     = uart_rx_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        `uvm_info("ENV", " connect phase !", UVM_LOW)
        //`uvm_analysis_imp_decl(_in)
        //`uvm_analysis_imp_decl(_out)
        // To connect mon_in analysis_port -> scb analysis_imp_in : write_in
        agt_in.mon_in.in_port.connect(scb.imp_in);
        // To connect mon_out analysis_port -> scb analysis_imp_out : write_out
        agt_out.mon_out.out_port.connect(scb.imp_out);
    endfunction

endclass

class uvm_test_uart extends uvm_test;
    // factory registy
    `uvm_component_utils(uvm_test_uart)
    uart_rx_environment env;
    uart_rx_sequence seq;

    function new(string name = "uvm_test_uart", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = uart_rx_environment::type_id::create("env", this);
        seq = uart_rx_sequence::type_id::create("seq", this);
    endfunction

    task run_phase(uvm_phase phase);
        super.run_phase(phase);
        `uvm_info("uvm test run", " run phase !", UVM_LOW)
        phase.raise_objection(this);
        seq.start(env.agt_in.sqr);
        phase.drop_objection(this);
        #10;
    endtask

    function void end_of_elaboration_phase(uvm_phase phase);
        uvm_root::get().print_topology();
    endfunction
endclass

module tb_uart_uvm ();
    logic clk = 0;
    uart_interface uart_if (clk);

    always #5 clk = ~clk;

    uart_top dut (
        .clk    (clk),
        .rst    (uart_if.rst),
        .rx     (uart_if.rx),       // from PC
        .rx_done(uart_if.rx_done),
        .rx_data(uart_if.rx_data)
    );

    initial begin
        uvm_config_db#(virtual uart_interface)::set(null, "*", "uart_vif",
                                                    uart_if);
        run_test("uvm_test_uart");
        $finish;
    end


endmodule
