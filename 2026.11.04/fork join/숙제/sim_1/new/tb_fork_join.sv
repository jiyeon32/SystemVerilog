`timescale 1ns / 1ps

module tb_fork_join();
/*
// fork join_any_,join
    initial begin
        #1 $display("%t : start fork - join_any and join", $time);

        fork
            // task A
            #10 A_thread();
            fork
                // task B
                #20 B_thread();
                #50 B_thread();
            join

            // task C
            #30 C_thread();
        join_any

        #10 $display("%t : end fork - join_any and join", $time);
    end 


    task A_thread();
        $display("%t : a thread", $time);
    endtask

    task B_thread();
        $display("%t : b thread", $time);
    endtask

    task C_thread();
        $display("%t : c thread", $time);
    endtask   
    endmodule

*/
/*
    // fork join_any
    initial begin
        #1 $display("%t : start fork - join_any", $time);

        fork
            // task A
            #10 A_thread();

            // task B
            #20 B_thread();

            // task C
            #15 C_thread();
        join_any

        #10 $display("%t : end fork - join_any", $time);

    end
*/

/*
    // fork join_none
    initial begin
        #1 $display("%t : start fork - join_none", $time);

        fork
            // task A
            #10 A_thread();

            // task B
            #20 B_thread();

            // task C
            #15 C_thread();
        join_none

        #10 $display("%t : end fork - join_none", $time);
    end

*/
/*
    // fork join
    initial begin
        #1 $display("%t : start fork - join", $time);

        fork
            // task A
            #10 A_thread();

            // task B
            #20 B_thread();

            // task C
            #15 C_thread();
        join

        #10 $display("%t : end fork - join", $time);
    end

    // fork join_any_,join
    initial begin
        #1 $display("%t : start fork - jjoin_any and join", $time);

        fork
            // task A
            #10 A_thread();
            fork
                // task B
                #20 B_thread();
                #50 B_thread();
            join

            // task C
            #30 C_thread();
        join_any

        #10 $display("%t : end fork - join_any and join", $time);
    end 
*/



    // fork join_any_,disable
    initial begin
        #1 $display("%t : start fork - join_any and disable", $time);

        fork
            // task A
            A_thread();
            // task B
            B_thread();
            // task C
            C_thread();
        join_any

        #10 $display("%t : end fork - join_any and disable", $time);
        disable fork;
        $stop;
    end 

    
    task A_thread();
        repeat (5) $display("%t : A thread", $time);
    endtask

    task B_thread();
        forever begin
            $display("%t : B thread", $time);
            #5;
        end  
    endtask

    task C_thread();
        forever begin
            $display("%t : C thread", $time);
            #10;
        end
    endtask
endmodule
