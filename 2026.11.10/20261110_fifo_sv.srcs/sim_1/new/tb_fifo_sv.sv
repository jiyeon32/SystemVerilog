`timescale 1ns / 1ps

interface fifo_interface (
    input clk
);
    logic       rst;
    logic [7:0] push_data;
    logic       push;
    logic       pop;
    logic [7:0] pop_data;
    logic       full;
    logic       empty;
endinterface

class transaction;
    rand bit            rst;
    rand bit [7:0] push_data;
    rand bit       push;
    rand bit       pop;
    logic    [7:0] pop_data;
    logic          full;
    logic          empty;

    function void debug_print(string name);
        $display(
            "%t : [%s] rst = %d, push_data = %d, push = %d, pop = %d, pop_data = %d, full = %d, empty = %d",
            $time, name, rst, push_data, push, pop, pop_data, full, empty);
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
            tr.rst = 0;
            gen2drv_mbox.put(tr);
            @(gen_next_evt);
        end
    endtask
    

    task fifo_1();
        tr = new;
        tr.randomize() with {rst == 1; push == 0; pop == 0; };
        gen2drv_mbox.put(tr);
        @(gen_next_evt);

        repeat(3) begin
            tr = new;
            tr.randomize() with {rst == 0; push == 1; pop == 0; };
            gen2drv_mbox.put(tr);
            @(gen_next_evt);
        end

        tr = new;
        tr.randomize() with {rst == 1; push == 0; pop == 0; };
        gen2drv_mbox.put(tr);
        @(gen_next_evt);

        tr = new;
        tr.randomize() with {rst == 0; push == 0; pop == 1; };
        gen2drv_mbox.put(tr);
        @(gen_next_evt);
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual fifo_interface fifo_vif;

    function new(mailbox#(transaction) gen2drv_mbox,
                 virtual fifo_interface fifo_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.fifo_vif     = fifo_vif;
    endfunction

    task preset();
        fifo_vif.rst = 1;
        repeat(2) @(negedge fifo_vif.clk);
        fifo_vif.rst = 0;
    endtask

    task run();
        forever begin
            @(posedge fifo_vif.clk);
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            #1;
            fifo_vif.rst = tr.rst;
            fifo_vif.push_data = tr.push_data;
            fifo_vif.push = tr.push;
            fifo_vif.pop = tr.pop;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual fifo_interface fifo_vif;

    function new(mailbox#(transaction) mon2scb_mbox,
                 virtual fifo_interface fifo_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.fifo_vif     = fifo_vif;
    endfunction

    task run();
        forever begin
            @(negedge fifo_vif.clk);
            tr = new;
            tr.rst = fifo_vif.rst;
            tr.push_data = fifo_vif.push_data;
            tr.push = fifo_vif.push;
            tr.pop = fifo_vif.pop;
            tr.pop_data = fifo_vif.pop_data;
            tr.full = fifo_vif.full;
            tr.empty = fifo_vif.empty;
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_evt;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    logic [7:0] expect_fifo[$:3];
    int total_count = 0, pass_count =  0, fail_count = 0;
    int full_empty_pass_count = 0, full_empty_fail_count = 0; 

    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("SCB");
            total_count ++;
            if(!tr.rst) begin
                assert((expect_fifo.size() == 0) === tr.empty) begin
                    full_empty_pass_count++;
                    $display("empty_pass");
                end else begin
                        full_empty_fail_count++;
                        $display("empty_fail");
                    end

                assert((expect_fifo.size() == 4) === tr.full) begin
                    full_empty_pass_count++;
                    $display("full_pass");
                end else begin
                        full_empty_fail_count++;
                        $display("full_fail");
                    end

                if(!tr.full & tr.push) begin
                    expect_fifo.push_back(tr.push_data);
                end
                if(!tr.empty & tr.pop) begin
                    if(expect_fifo.pop_front() === tr.pop_data) begin
                        pass_count++;
                        $display("pass");
                    end
                    else begin
                        fail_count++;
                        $display("fail");
                    end
                end
            end else begin
                expect_fifo.delete();
                assert (tr.empty & !tr.full)
                else  $display("error");
            end 
            -> gen_next_evt;
        end
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

    function new(virtual fifo_interface fifo_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;

        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, fifo_vif);
        mon = new(mon2scb_mbox, fifo_vif);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction

    task run(int run_count);
        drv.preset();
        fork
            gen.fifo_1();
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $display("end fifo test !!");
    endtask
endclass

module tb_fifo_sv ();

    logic clk = 0;
    fifo_interface fifo_if (clk);
    environment env;

    fifo_sv dut (
        .clk      (clk),
        .rst      (fifo_if.rst),
        .push_data(fifo_if.push_data),
        .push     (fifo_if.push),
        .pop      (fifo_if.pop),
        .pop_data (fifo_if.pop_data),
        .full     (fifo_if.full),
        .empty    (fifo_if.empty)
    );

    always #5 clk = ~clk;

    initial begin
        env = new(fifo_if);
        env.run(10);
        $finish;
    end
endmodule

