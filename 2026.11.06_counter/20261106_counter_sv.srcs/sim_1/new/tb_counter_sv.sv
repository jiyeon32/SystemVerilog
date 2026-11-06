`timescale 1ns / 1ps

class transaction;
    rand bit       rst;
    rand bit       mode;
    rand bit       run_stop;
    rand bit       clear;
    logic    [7:0] counter;

    bit list[6] = '{0,0,0,1,1,1};

    function void debug_print(string name);
        $display(
            "%t : [%s] rst = %d, mode = %d, run_stop = %d, clear = %d, counter = %d",
            $time, name, rst, mode, run_stop, clear, counter);
    endfunction

    /*constraint 3_cycle {

    } */

endclass

interface counter_interface (
    input clk
);
    logic       rst;
    logic       mode;
    logic       run_stop;
    logic       clear;
    logic [7:0] counter;

    property rst_zero;
        @(posedge clk) rst |=> (counter == 8'd0);
    endproperty

    a_rst_zero : assert property(rst_zero)
    else begin
        $display (" [Interface] rst = %d counter value error !! %d", rst, counter);
    end
endinterface

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    // To control for generator task run
    bit enable = 1;

    task run();
        while (enable) begin
            tr          = new;
            assert (tr.randomize())
            else $display ("[GEN] tr.randomized error !!!");
            // mode = 0 upcount, run_stop = 1, clear = 0
            tr.rst      = 0;
            //tr.mode     = 0;
            //tr.run_stop = 1;
            //tr.clear    = 0;
            gen2drv_mbox.put(tr);
            tr.debug_print("GEN");
            @(gen_next_evt);
        end
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual counter_interface counter_vif;
    event gen_next_evt;

    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt,
                 virtual counter_interface counter_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
        this.counter_vif  = counter_vif;
    endfunction

    task preset();
        counter_vif.rst      = 1;
        counter_vif.mode     = 0;
        counter_vif.run_stop = 0;
        counter_vif.clear    = 0;
        @(negedge counter_vif.clk);
        @(negedge counter_vif.clk);
        counter_vif.rst = 0;
    endtask

    task run();
        forever begin
            @(negedge counter_vif.clk);
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            counter_vif.rst      = tr.rst;
            counter_vif.mode     = tr.mode;
            counter_vif.run_stop = tr.run_stop;
            counter_vif.clear    = tr.clear;
            ->gen_next_evt;
        end
    endtask


endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual counter_interface counter_vif;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual counter_interface counter_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.counter_vif  = counter_vif;
    endfunction

    task run();
        forever begin
            @(posedge counter_vif.clk);
            tr          = new();
            tr.rst      = counter_vif.rst;
            tr.mode     = counter_vif.mode;
            tr.run_stop = counter_vif.run_stop;
            tr.clear    = counter_vif.clear;
            tr.counter  = counter_vif.counter;
            mon2scb_mbox.put(tr);
            tr.debug_print("MON");
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    // pass fail
    logic [7:0] expected_count = 0;
    int pass_cnt = 0, fail_cnt = 0, total_cnt = 0;

    function new(mailbox#(transaction) mon2scb_mbox);
        this.mon2scb_mbox = mon2scb_mbox;
    endfunction

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            if (!tr.rst & !tr.clear) begin
                total_cnt++;
                if (expected_count == tr.counter) begin
                    pass_cnt++;
                end else begin
                    $display("fail");
                    fail_cnt++;
                end
                $display("expected_count = %d", expected_count);
                if (tr.run_stop) begin
                    if (tr.mode) begin
                        expected_count--;  // mode 1 : down count
                    end else begin
                        expected_count++;
                    end
                end
            end else begin
                expected_count = 0;
            end
        end
    endtask

    task report();
        $display("******************************");
        $display("** counter 256 test program **");
        $display("****** total test = %4d ******", total_cnt);
        $display("****** pass count = %4d ******", pass_cnt);
        $display("****** fail count = %4d ******", fail_cnt);
        $display("******************************");
        $display("***   end counter 256 test  **");
        $display("******************************");


    endtask
endclass

class environment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    event                  gen_next_evt;

    function new(virtual counter_interface counter_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, gen_next_evt, counter_vif);
        mon = new(mon2scb_mbox, counter_vif);
        scb = new(mon2scb_mbox);
    endfunction

    task run(int run_count);
        drv.preset();
        gen.enable = 1;  // raise up
        fork
            gen.run();
            drv.run();
            mon.run();
            scb.run();
        join_none

        #3000;
        gen.enable = 0;
        #10;
        scb.report();

        disable fork;
    endtask

endclass


module tb_counter_sv ();

    logic clk = 0;
    environment env;
    counter_interface counter_if (clk);

    counter_256 dut (
        .clk     (clk),
        .rst     (counter_if.rst),
        .mode    (counter_if.mode),
        .run_stop(counter_if.run_stop),
        .clear   (counter_if.clear),
        .counter (counter_if.counter)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(counter_if);
        env.run(256);
        $finish;

    end



endmodule
