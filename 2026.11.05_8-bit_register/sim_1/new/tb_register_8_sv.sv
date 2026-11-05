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
        repeat(run_count) begin
            tr = new;
            tr.randomize();
            gen2drv_mbox.put(tr); // to driver
            @(gen_next_evt); // from scoreboard
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

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            @(posedge reg_vif.clk);
            #1
            reg_vif.d = tr.d;
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
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction
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
        gen = new(gen2drv_mbox,gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, reg_vif);
        mon = new(mon2scb_mbox, mon_next_evt, reg_vif);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction
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
        $finish;
    end
endmodule
