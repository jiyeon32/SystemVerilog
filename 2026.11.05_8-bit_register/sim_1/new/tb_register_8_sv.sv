`timescale 1ns / 1ps

interface reg_interface (
    input clk
);
    logic       reset;
    logic [7:0] d;
    logic [7:0] q;
endinterface

// seq item
class transaction;
    bit            reset;
    rand bit [7:0] d;
    logic    [7:0] q;

    function debug_prin(string name);
        $display("%t : [%s] reset = %d, d = %d, q = %d", $time, name, reset, d, q);
    endfunction
endclass

class generator;
    transaction tr;

    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr);  // to driver
            tr.debug_prin("GEN");
            @(gen_next_evt);  // from scoreboard
        end
    endtask
endclass

class driver;
    transaction tr;

    mailbox #(transaction) gen2drv_mbox;
    event mon_next_evt;
    virtual reg_interface reg_vif;


    function new(mailbox#(transaction) gen2drv_mbox, event mon_next_evt,
                 virtual reg_interface reg_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.mon_next_evt = mon_next_evt;
        this.reg_vif      = reg_vif;
    endfunction

    task preset();
        reg_vif.reset = 1;
        @(posedge reg_vif.clk);
        @(posedge reg_vif.clk);
    endtask

    task run();
        forever begin
            @(posedge reg_vif.clk);
            gen2drv_mbox.get(tr);
            tr.debug_prin("DRV - GET");
            #1;
            tr.debug_prin("DRV - AFTER POSEDGE");
            reg_vif.reset = 0;
            reg_vif.d = tr.d;
            ->mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_evt;
    virtual reg_interface reg_vif;

    function new(mailbox#(transaction) mon2scb_mbox, event mon_next_evt,
                 virtual reg_interface reg_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.mon_next_evt = mon_next_evt;
        this.reg_vif      = reg_vif;
    endfunction

    task run();
        forever begin
            tr   = new;
            @(mon_next_evt);
            tr.debug_prin("MON");
            @(posedge reg_vif.clk);
            tr.d = reg_vif.d;
            tr.q = reg_vif.q;
            tr.debug_prin("MON - AFTER POSEDGE");
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction                  tr;
    mailbox #(transaction)       mon2scb_mbox;
    event                        gen_next_evt;

    logic                  [7:0] expected_d;  // for case compare
    bit                          first_flag = 1;
    ;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run();
        forever begin
            // get mail box
            tr = new;
            mon2scb_mbox.get(tr);
            tr.debug_prin("SCB");
            if (first_flag) begin
                first_flag = 0;
            end else begin
                // pass / fail
                if (expected_d === tr.q) begin
                    $display("pass");
                end else begin
                    $display("fail");
                end
            end
            // store expevted_d = tr.d
            expected_d = tr.d;
            //event
            ->gen_next_evt;
        end
    endtask

endclass

class environment;
    generator gen;
    driver drv;
    monitor mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event gen_next_evt;
    event mon_next_evt;

    function new(virtual reg_interface reg_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, reg_vif);
        mon = new(mon2scb_mbox, mon_next_evt, reg_vif);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction

    task run(int run_count);
        drv.preset();
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        // pass/fail count display
        $display("end register 8bit verification program");

    endtask
endclass

module tb_register_8_sv ();

    logic clk;

    reg_interface reg_if (clk);
    environment env;

    register_8 dut (
        .clk  (clk),
        .reset(reg_if.reset),
        .d    (reg_if.d),
        .q    (reg_if.q)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        env = new(reg_if);
        // run program
        env.run(20);
        $finish;
    end
endmodule
