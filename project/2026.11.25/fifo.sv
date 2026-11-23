`timescale 1ns / 1ps

module fifo #(
    parameter DEPTH = 4,
    parameter A_BIT_WIDTH = $clog2(DEPTH),
    parameter D_BIT_WIDTH = 8
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    push,
    input  logic                    pop,
    input  logic [D_BIT_WIDTH -1:0] push_data,
    output logic [D_BIT_WIDTH -1:0] pop_data,
    output logic                    full,
    output logic                    empty
);

    logic [A_BIT_WIDTH-1:0] w_wptr, w_rptr;

    register_file #(
        .DEPTH      (DEPTH),
        .D_BIT_WIDTH(D_BIT_WIDTH)
    ) U_REG_FILE (
        .clk  (clk),
        .we   ((~full & push)),
        .wdata(push_data),
        .waddr(w_wptr),
        .raddr(w_rptr),
        .rdata(pop_data)
    );

    control_unit #(
        .A_BIT_WIDTH(A_BIT_WIDTH)
    ) U_CONTROL_UNIT (
        .clk  (clk),
        .rst  (rst),
        .push (push),
        .pop  (pop),
        .wptr (w_wptr),
        .rptr (w_rptr),
        .full (full),
        .empty(empty)
    );


endmodule

module register_file #(
    parameter DEPTH = 4,
    parameter A_BIT_WIDTH = $clog2(DEPTH),
    parameter D_BIT_WIDTH = 8
) (
    input  logic                       clk,
    input  logic                       we,
    input  logic [A_BIT_WIDTH-1:0] waddr,
    input  logic [A_BIT_WIDTH-1:0] raddr,
    output logic [    D_BIT_WIDTH-1:0] rdata,
    input  logic [    D_BIT_WIDTH-1:0] wdata
);

    // ram
    logic [D_BIT_WIDTH-1:0] register_file[0:DEPTH-1];

    //write SL
    always_ff @(posedge clk) begin
        if (we) begin
            register_file[waddr] <= wdata;
        end
    end

    // read CL
    assign rdata = register_file[raddr];
endmodule

module control_unit #(
    parameter A_BIT_WIDTH = 2
) (
    input  logic                      clk,
    input  logic                      rst,
    input  logic                      push,
    input  logic                      pop,
    output logic [A_BIT_WIDTH -1 : 0] wptr,
    output logic [A_BIT_WIDTH -1 : 0] rptr,
    output logic                      full,
    output logic                      empty
);

    logic [A_BIT_WIDTH-1:0] wptr_reg, wptr_next;
    logic [A_BIT_WIDTH-1:0] rptr_reg, rptr_next;
    logic full_reg, full_next;
    logic empty_reg, empty_next;

    assign wptr  = wptr_reg;
    assign rptr  = rptr_reg;
    assign full  = full_reg;
    assign empty = empty_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            wptr_reg  <= 0;
            rptr_reg  <= 0;
            full_reg  <= 1'b0;
            empty_reg <= 1'b1;
        end else begin
            wptr_reg  <= wptr_next;
            rptr_reg  <= rptr_next;
            full_reg  <= full_next;
            empty_reg <= empty_next;
        end
    end

    //next, output
    always_comb begin
        wptr_next  = wptr_reg;
        rptr_next  = rptr_reg;
        full_next  = full_reg;
        empty_next = empty_reg;

        // {,} concatenation operator
        case ({push, pop})
            2'b10: begin
                // push only
                if (!full_reg) begin
                    empty_next = 1'b0;
                    wptr_next  = wptr_reg + 1;
                    if (wptr_next == rptr_reg) begin
                        full_next = 1'b1;
                    end
                end
            end

            2'b01: begin
                // pop only
                if (!empty_reg) begin
                    full_next = 1'b0;
                    rptr_next = rptr_reg + 1;
                    if (rptr_next == wptr_reg) begin
                        empty_next = 1'b1;
                    end
                end
            end

            2'b11: begin
                // push/pop
                if (full_reg) begin
                    rptr_next = rptr_reg + 1;
                    full_next = 1'b0;
                end else if (empty_reg) begin
                    wptr_next  = wptr_reg + 1;
                    empty_next = 1'b0;
                end else begin
                    wptr_next = wptr_reg + 1;
                    rptr_next = rptr_reg + 1;
                end
            end
        endcase
    end

endmodule
