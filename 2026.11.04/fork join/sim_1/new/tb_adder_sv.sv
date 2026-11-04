`timescale 1ns / 1ps

class transaction;
    // drive variable
    rand bit [7:0] a;
    rand bit [7:0] b;
    rand bit       mode;
    // monitor variable
    logic    [7:0] s;
    logic          c;

    // range constraint
    constraint adder_limit {
        a > 128;
        b < 64;
    }

    //constraint adder_inside {a inside {[128:200]};}
    constraint adder_inside {
        a inside {128, 200, 212, 250};
    }  //제약조건을 list로

    constraint adder_distribute {
        mode dist{              // 0이 80%확률로 나올때 1은 20%의 확률로 나와라
            0 :/ 80,  // :/ %개념 모두(80,20) 더해서 
            1 :/ 20
        };
    }

    function debug_print(string name);
        $display("%t : [%s] a = %d, b = %d, mode = %d, s = %d, c = %d", $time,
                 name, a, b, mode, s, c);
    endfunction
endclass

interface adder_interface ();
    logic [7:0] a, b;
    logic       mode;
    logic [7:0] s;
    logic       c;
endinterface


class generator;
    transaction tr;  //handle

    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;
    function new(mailbox#(transaction) gen2drv_mbox, event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        repeat (run_count) begin
            tr = new;
            // to generate for randomize stimulus by tr
            tr.randomize();
            tr.debug_print("GEN");
            gen2drv_mbox.put(tr);
            // wait gen_next event
            @(gen_next_evt);
        end
        #10;
        $display("%t : end gen", $time);
    endtask
endclass

class driver;
    transaction tr;
    event drv2mon_evt;
    mailbox #(transaction) gen2drv_mbox;  // 위에와 이름만 같음
    virtual adder_interface adder_if_v;

    function new(mailbox#(transaction) gen2drv_mbox_a, event drv2mon_evt,
                 virtual adder_interface adder_if_v_a);
        this.gen2drv_mbox = gen2drv_mbox_a;  // mailbox
        this.drv2mon_evt  = drv2mon_evt;  // event
        this.adder_if_v   = adder_if_v_a;  // virtual connection
    endfunction

    task run();
        forever begin
            gen2drv_mbox.get(tr);
            tr.debug_print("DRV");
            // drive
            adder_if_v.a = tr.a;
            adder_if_v.b = tr.b;
            adder_if_v.mode = tr.mode;
            #5;
            ->drv2mon_evt;  // "->" event를 발생시켜라
            #5;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual adder_interface adder_if_v;
    event drv2mon_evt;
    function new(mailbox#(transaction) mon2scb_mbox, event drv2mon_evt,
                 virtual adder_interface adder_if_v);
        this.mon2scb_mbox = mon2scb_mbox;
        this.drv2mon_evt  = drv2mon_evt;
        this.adder_if_v   = adder_if_v;
    endfunction

    task run();
        forever begin
            // wait event
            @(drv2mon_evt);
            // wait(drv2mon_evt); 
            // generate transaction
            tr = new;  // 이 내부(class moniotr)에서 선언한 tr
            tr.a = adder_if_v.a;
            tr.b = adder_if_v.b;
            tr.mode = adder_if_v.mode;
            tr.s = adder_if_v.s;
            tr.c = adder_if_v.c;
            tr.debug_print("MON");
            mon2scb_mbox.put(tr);
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_evt;

    // pass/fail
    bit [7:0] expected_s;
    bit expected_c;
    int pass_cnt = 0, fail_cnt = 0;

    function new(mailbox#(transaction) mon2scb_mbox, event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction


    task run();
        forever begin
            // get transaction 
            mon2scb_mbox.get(tr);
            if (tr.mode) begin
                {expected_c, expected_s} = tr.a - tr.b;
            end else begin
                {expected_c, expected_s} = tr.a + tr.b;
            end

            // pass fail
            if ({expected_c, expected_s} == {tr.c, tr.s}) begin
                // pass
                $display("pass");
                pass_cnt++;
            end else begin
                // fail
                $display("fail");
                fail_cnt++;
            end
            tr.debug_print("SCB");
            -> gen_next_evt;
        end
    endtask
endclass


class enviroment;
    generator              gen;
    driver                 drv;
    monitor                mon;
    scoreboard             scb;
    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;
    event                  drv2mon_evt;
    event                  gen_next_evt;
    function new(virtual adder_interface adder_if_v);
        gen2drv_mbox = new;
        mon2scb_mbox = new;
        gen = new(gen2drv_mbox, gen_next_evt);
        drv = new(gen2drv_mbox, drv2mon_evt, adder_if_v);
        mon = new(mon2scb_mbox, drv2mon_evt, adder_if_v);
        scb = new(mon2scb_mbox, gen_next_evt);
    endfunction

    // fork join none control
    task run(int run_count);
        fork
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        ;
        $display("%t: end fork join", $time);
        #100;
        $display("pass count = %d", scb.pass_cnt);
        $display("fail count = %d", scb.fail_cnt);
    endtask
endclass

module tb_adder_sv ();
    adder_interface adder_if ();
    enviroment env;

    adder dut (
        .a   (adder_if.a),
        .b   (adder_if.b),
        .mode(adder_if.mode),
        .s   (adder_if.s),
        .c   (adder_if.c)
    );

    initial begin
        env = new(adder_if);
        env.run(20);
        $finish;
    end

endmodule
