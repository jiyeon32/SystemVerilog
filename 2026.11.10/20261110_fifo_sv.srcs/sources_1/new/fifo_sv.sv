`timescale 1ns / 1ps

module fifo_sv (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] push_data,
    input  logic       push,
    input  logic       pop,
    output logic [7:0] pop_data,
    output logic       full,
    output logic       empty
);

    logic [1:0] waddr, raddr;
    
    register_file U_REG_FILE (
        .*,
        .waddr(waddr),
        .raddr(raddr),
        .we(push&(~full))
    );

    control_unit U_CONTROL_UNIT (
        .*,
        .wptr (waddr),
        .rptr (raddr)
    );

endmodule

module register_file (
    input  logic       clk,
    input  logic [1:0] waddr,
    input  logic [1:0] raddr,
    input  logic [7:0] push_data,
    input  logic       we,
    output logic [7:0] pop_data
);

    logic [7:0] register_file[0:3];

    always_ff @(posedge clk) begin
        if (we) begin
            register_file[waddr] <= push_data;
        end
    end

    assign pop_data = register_file[raddr];
endmodule

module control_unit (
    input  logic       clk,
    input  logic       rst,
    input  logic       push,
    input  logic       pop,
    output logic [1:0] wptr,
    output logic [1:0] rptr,
    output logic       full,
    output logic       empty
);

    logic [1:0] wptr_next,rptr_next;
    logic full_next, empty_next;


    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            wptr  <= 0;
            rptr  <= 0;
            empty <= 1;
            full  <= 0;
        end else begin
            wptr <= wptr_next;
            rptr <= rptr_next;
            full <= full_next;
            empty <= empty_next;
        end
    end

    always_comb begin
        wptr_next = wptr;
        rptr_next = rptr;
        full_next = full;
        empty_next = empty;
        case ({
            push, pop
        })

            2'b10 : begin
                // push only
                if(!full) begin
                    wptr_next = wptr + 1;
                    empty_next = 1'b0;
                    if(wptr_next == rptr) begin
                        full_next = 1'b1;
                    end
                end
            end

            2'b01 : begin
                // pop only
                if(!empty) begin
                    rptr_next = rptr + 1;
                    full_next = 1'b0;
                    if(rptr_next == wptr) begin
                        empty_next = 1'b1;
                    end
                end
            end

            2'b11 : begin
                // push/pop
                if(full) begin
                    rptr_next = rptr + 1;
                    full_next = 1'b0;
                end else if(empty) begin
                    wptr_next = wptr + 1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr + 1;
                    rptr_next = rptr + 1;

                end
            end





        endcase
    end
endmodule
