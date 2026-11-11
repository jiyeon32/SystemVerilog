`timescale 1ns / 1ps

interface fifo_interface(input clk);

    logic       rst;
    logic [7:0] push_data;
    logic       push;
    logic       pop;
    logic [7:0] pop_data;
    logic       full;
    logic       empty;

  
    property rst_full;
        @(posedge clk) rst |-> (full === 1'b0); //x,z 포함해서 비교
    endproperty
    property rst_empty;
        @(posedge clk) rst |-> (empty === 1'b1); //x,z 포함해서 비교
    endproperty

    a_rst_full :  assert property(rst_full)
     else $display("%t assert error full %d", $time,full);
    a_rst_empty :  assert property(rst_empty)
    else $display("%t assert error empty %d", $time,empty);

endinterface

class transaction;
    rand bit    rst;
    rand bit[7:0]  push_data;
    rand bit    push;
    rand bit    pop;
    logic [7:0] pop_data;
    logic       full;
    logic       empty;

    int         scenario;
    constraint test_1{
        if(scenario == 1) { 
        push dist{
            0:/0,
            1:/10
        };
        pop dist{
            0:/10,
            1:/0
        };
        
        }  
        if(scenario == 2) { 
        push dist{
            0:/10,
            1:/0
        };
        pop dist{
            0:/0,
            1:/10
        };
        } 

    }


    function void debug_print(string name);
        $display("%t : [%s] rst=%d push(%d) = [%d], full(%d) / pop(%d) = [%d], empty(%d)  "
                ,$time, name, rst, push, push_data, full, pop, pop_data,empty);
    endfunction

endclass 

class generator;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    event gen_next_evt;

    function new(mailbox #(transaction) gen2drv_mbox,
                event gen_next_evt);
        this.gen2drv_mbox = gen2drv_mbox;
        this.gen_next_evt = gen_next_evt;
    endfunction

    task run(int run_count);
        int push_only_count = 10, pop_only_count =10;
       //push test
       $display("push only =%d",push_only_count);
       repeat(push_only_count) begin
            tr = new;
            tr.scenario = 1;
            tr.randomize();

            gen2drv_mbox.put(tr);
            tr.rst =0;
            tr.debug_print("gen");
            @(gen_next_evt);
       end
       //pop test
       $display("pop only =%d",pop_only_count);
        repeat(pop_only_count) begin
            tr = new;
            tr.scenario = 2;
            tr.randomize();

            gen2drv_mbox.put(tr);
            tr.rst =0;
            tr.debug_print("gen");
            @(gen_next_evt);
       end
       //ramdom
       $display("pop only =%d",run_count);
        repeat(run_count) begin
            tr = new;
            tr.scenario = 3;
            tr.randomize();

            gen2drv_mbox.put(tr);
            tr.rst =0;
            tr.debug_print("gen");
            @(gen_next_evt);
       end
    endtask
endclass

class driver;
    transaction tr;
    mailbox #(transaction) gen2drv_mbox;
    virtual fifo_interface fifo_vif;

    function new(mailbox #(transaction) gen2drv_mbox,
                virtual fifo_interface fifo_vif);
        this.gen2drv_mbox = gen2drv_mbox;
        this.fifo_vif     = fifo_vif;
    endfunction

    task preset();
        fifo_vif.rst = 1;
        fifo_vif.push =0;
        fifo_vif.push_data = 0;
        fifo_vif.pop = 0;
        repeat(2) @(negedge fifo_vif.clk);
        fifo_vif.rst = 0;
    endtask

    task run();
        forever begin
            @(posedge fifo_vif.clk);
            gen2drv_mbox.get(tr);
            tr.debug_print("drv");
            #1;
            fifo_vif.rst        = tr.rst;
            fifo_vif.push       = tr.push;
            fifo_vif.push_data  = tr.push_data;
            fifo_vif.pop        = tr.pop;
        end
    endtask
endclass

class monitor;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    virtual fifo_interface fifo_vif;
    
    function new(mailbox #(transaction) mon2scb_mbox,
                virtual fifo_interface fifo_vif);
        this.mon2scb_mbox = mon2scb_mbox;
        this.fifo_vif     = fifo_vif;
    endfunction

    task run();
        forever begin
            @(negedge fifo_vif.clk);
            tr = new;
            tr.rst        = fifo_vif.rst;  
            tr.push_data  = fifo_vif.push_data;
            tr.push       = fifo_vif.push;
            tr.pop_data   = fifo_vif.pop_data;
            tr.pop        = fifo_vif.pop;
            tr.full        = fifo_vif.full;
            tr.empty        = fifo_vif.empty;
            mon2scb_mbox.put(tr);
            tr.debug_print("mon");
        end
    endtask
endclass

class scoreboard;
    transaction tr;
    mailbox #(transaction) mon2scb_mbox;
    event gen_next_evt;
    int fifo_size = 0;

    logic [7:0] expected_fifo[$:3];
    int total_cnt = 0, pass_cnt =0, fail_cnt = 0;
    int empty_pass_cnt=0, empty_fail_cnt;
    int full_pass_cnt =0, full_fail_cnt;
    bit expect_full = 0, expect_empty = 1;

    covergroup cg_fifo;
        option.per_instance = 1;
        //fifo push data 
        //iff(tr.push) : push 1 인 경우에만 판단 
        cp_push_data : coverpoint tr.push_data iff(tr.push){
            bins full[] = {[0:255]};  //범위지정. 이 범위 중 출력된 값이 %로 나타남. 256개 중 몇개 -> x%
        }

        //각각의 경우가 발생하는지 확인. 1번씩만
        //fifo  push_pop : op
        cp_push_pop : coverpoint{tr.push, tr.pop} {
            bins idle      = {2'b00};
            bins push_only = {2'b10};
            bins pop_only  = {2'b01};
            bins push_pop  = {2'b11};
        }

        //full_empty :state
        cp_full_empty : coverpoint{tr.full, tr.empty} {
            bins nomal      = {2'b00};
            bins full       = {2'b10};
            bins empty      = {2'b01};
           // bins full_empty  = {2'b11}; //나올 수 없는 경우, 100%으로 나오면 에러 :복잡하니 일단 주석처리함
        }


        //check in fifo depth
        
        cp_fifo_size : coverpoint fifo_size {
//            bins size_0 = {0};
//            bins size_1 = {1};
//            bins size_1 = {2};
//            bins size_1 = {3};
//            bins size_1 = {4};

            bins size[] = {[0:4]};
        }
        cx_op_st : cross cp_push_pop,cp_full_empty;
        //수정) full일때 4만 나옴  0,1,2,3 빠짐 -> full, empty 제거
        cx_op_fifo_depth : cross cp_push_pop,cp_fifo_size;
    endgroup

    function new(mailbox #(transaction) mon2scb_mbox,
                event gen_next_evt);
        this.mon2scb_mbox = mon2scb_mbox;
        this.gen_next_evt =  gen_next_evt;
        this.cg_fifo = new;
    endfunction


    task run();
        forever begin
            mon2scb_mbox.get(tr);
            tr.debug_print("scb");
            total_cnt++;
            if(!tr.rst) begin
                fifo_size = expected_fifo.size();
                if(fifo_size==4) begin
                    expect_full = 1;
                end else expect_full = 0;
                if(fifo_size==0) begin
                    expect_empty = 1;
                end else expect_empty = 0;

                //full  pass/fail
                if(expect_full == tr.full) begin
                    $display("pass : fifo full siganl");
                    full_pass_cnt++;
                end else begin
                     $display("fail : fifo full siganl");
                    full_fail_cnt++;
                end

                //empty pass/fail
                if(expect_empty == tr.empty) begin
                    $display("pass : fifo empty siganl");
                    empty_pass_cnt++;
                end else begin
                     $display("fail : fifo empty siganl");
                    empty_fail_cnt++;
                end


                if(!expect_full & tr.push) begin
                    expected_fifo.push_back(tr.push_data);
                end
                if(!expect_empty & tr.pop)begin
                    if(expected_fifo.pop_front()===tr.pop_data) begin
                        $display("pass");
                        pass_cnt++;
                    end
                    else begin
                        $display("fail");
                        fail_cnt++;
                    end
                end
                //coverage update
               cg_fifo.sample();
            end
            ->gen_next_evt;
        end
    endtask

    task report();
        $display("***********************************");
        $display("******fifo verification test*******");    
        $display("******total test num  =  %4d*******", total_cnt);
        $display("****** pass test num  =  %4d*******", pass_cnt);
        $display("****** fail test num  =  %4d*******", fail_cnt);
        $display("***********************************");
        $display("****** full pass test  = %4d*******", full_pass_cnt);
        $display("****** full fail test  = %4d*******", full_fail_cnt);
        $display("******empty pass test  = %4d*******", empty_pass_cnt);
        $display("******empty fail test  = %4d*******", empty_fail_cnt);
        $display("***********************************");
        $display("  fifo coverag push data = %4.2f %% ", cg_fifo.cp_push_data.get_coverage());
        $display("  coverag push,pop op = %4.2f %%    ", cg_fifo.cp_push_pop.get_coverage());
        $display("  coverag full empty  = %4.2f %%    ", cg_fifo.cp_full_empty.get_coverage());
        $display("***********************************");
        $display("  fifo size coverag  = %4.2f %%     ", cg_fifo.cp_fifo_size.get_coverage());
        $display("***********************************");
        $display("  coverag cross op_st = %4.2f %%    ", cg_fifo.cx_op_st.get_coverage());
        $display("  coverag depth op_st = %4.2f %%    ", cg_fifo.cx_op_fifo_depth.get_coverage());
        
    endtask
endclass

class environment;
    generator   gen;
    driver      drv; 
    monitor     mon;
    scoreboard scb;

    mailbox #(transaction) gen2drv_mbox;
    mailbox #(transaction) mon2scb_mbox;

    event gen_next_evt;

    
    
    function new(virtual fifo_interface fifo_vif);
        gen2drv_mbox = new;
        mon2scb_mbox = new;

        gen = new(gen2drv_mbox,  gen_next_evt);
        drv = new(gen2drv_mbox, fifo_vif);
        mon = new(mon2scb_mbox, fifo_vif);
        scb = new(mon2scb_mbox, gen_next_evt); 
    endfunction

    task run(int run_count);
        drv.preset;
        fork 
            gen.run(run_count);
            drv.run();
            mon.run();
            scb.run();
        join_any
        #10;
        $display("end fifo test");
        scb.report();

    endtask
endclass

module tb_fifo_sv_2();
   
    logic clk = 0;
    fifo_interface fifo_if(clk); 
    environment env;


    fifo_sv dut_fifo(
        .clk        (clk),
        .rst        (fifo_if.rst),
        .push_data  (fifo_if.push_data),
        .push       (fifo_if.push),
        .pop         (fifo_if.pop),
        .pop_data   (fifo_if.pop_data),
        .full       (fifo_if.full),
        .empty      (fifo_if.empty)
    );

    always #5 clk = ~clk;
    initial begin
        env =new(fifo_if);
        env.run(256);
        $finish;
    end
endmodule
