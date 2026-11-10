`timescale 1ns / 1ps

interface ram_interface (
    input logic clk
);
    logic [5:0] addr;
    logic [7:0] wdata;
    logic       we;
    logic [7:0] rdata;

endinterface

class transaction;
    rand bit [5:0] addr;
    rand bit [7:0] wdata;
    rand bit       we;
    logic    [7:0] rdata;

    function void debug_print(string name);
        $display("%t : [%s] addr = %d, wdata = %d, we = %d, rdata = %d", $time,
                 name, addr, wdata, we, rdata);
    endfunction
endclass

class generator;
    transaction tr;
    transaction tr_scb;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) gen2drv_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_evt);
        this.gen2scb_mbox = gen2scb_mbox;
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            tr_scb = new;
            tr.randomize();

            // copy
            tr_scb.addr = tr.addr;
            tr_scb.wdata = tr.wdata;
            tr_scb.we = tr.we;
            tr_scb.rdata = tr.rdata;

            gen2drv_mbox.put(tr);
            gen2scb_mbox.put(tr);
            tr.debug_print("GEN");
            tr_scb.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event mon_next_evt;
    virtual ram_interface ram_vif;

    function new(mailbox#(transaction) gen2drv_mbox, event mon_next_evt,
                 virtual ram_interface ram_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.mon_next_evt = mon_next_evt;
        this.ram_vif = ram_vif;
    endfunction

    task run();
        forever begin
            @(negedge ram_vif.clk);
            gen2drv_mbox.get(tr);
            ram_vif.addr  = tr.addr;
            ram_vif.wdata = tr.wdata;
            ram_vif.we    = tr.we;
            tr.debug_print("DRV");
            ->>mon_next_evt;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event mon_next_evt;
    virtual ram_interface ram_vif;

    function new(mailbox#(transaction) mon2scb_mbox, event mon_next_evt,
                 virtual ram_interface ram_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.mon_next_evt = mon_next_evt;
        this.ram_vif      = ram_vif;
    endfunction

    task run();
        forever begin
            wait (mon_next_evt.triggered);
            @(negedge ram_vif.clk);
            tr       = new;
            tr.addr  = ram_vif.addr;
            tr.wdata = ram_vif.wdata;
            tr.we    = ram_vif.we;
            tr.rdata = ram_vif.rdata;
            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    transaction tr_gen;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;

    event gen_next_evt;

    function new(mailbox#(transaction) mon2scb_mbox,
                 mailbox#(transaction) gen2scb_mbox, event gen_next_evt);
        this.gen2scb_mbox = gen2scb_mbox;
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    logic [7:0] expected_buf[0:63];
    //logic [7:0] expected_data;
    int total_count = 0, pass_count = 0, fail_count = 0;

    task run();
        forever begin
            gen2scb_mbox.get(tr_gen);
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            total_count++;
            if (tr_gen.we) begin
                // store for expected buffer
                expected_buf[tr_gen.addr] = tr_gen.wdata;
                // pass fail
                if ( expected_buf[tr_gen.addr] === tr.rdata) begin
                    // case compare
                    $display("Pass");
                    pass_count++;
                end else begin
                    $display("Fail");
                    fail_count++;
                end
            end else begin
                if ( expected_buf[tr_gen.addr] === tr.rdata) begin
                    // case compare
                    $display("Pass");
                    pass_count++;
                end else begin
                    $display("Fail");
                    fail_count++;
                end
            end
            ->gen_next_evt;
        end
    endtask

    task report();
        $display("*******************************");
        $display("*ram size 64,write / read test*");
        $display("*******************************");
        $display("*** ram total test num = %d ***", total_count);
        $display("*** ram pass  test num = %d ***", pass_count);
        $display("*** ram fail  test num = %d ***", fail_count);
        $display("*******************************");
    endtask
endclass

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    mailbox #(transaction) gen2scb_mbox;
    event                  gen_next_evt;
    event                  mon_next_evt;

    function new(virtual ram_interface ram_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen2scb_mbox = new;

        gen = new(gen2drv_mbox, gen2scb_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, mon_next_evt, ram_vif);
        mon = new(mon2scb_mbox, mon_next_evt, ram_vif);
        scb = new(mon2scb_mbox, gen2scb_mbox, gen_next_evt);
    endfunction

    task run(int run_count);
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any

        #10;
        scb.report();
    endtask
endclass


module tb_ram_sv_3 ();

    logic clk = 0;
    ram_interface ram_if (clk);
    environment env;

    ram_ip_sv dut (
        .clk  (clk),
        .addr (ram_if.addr),
        .wdata(ram_if.wdata),
        .we   (ram_if.we),
        .rdata(ram_if.rdata)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(ram_if);
        env.run(100);
        $finish;
    end


endmodule
