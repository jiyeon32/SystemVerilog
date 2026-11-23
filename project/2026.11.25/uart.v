`timescale 1ns / 1ps

module uart_fifo_loopback (
    input  logic       clk,
    input  logic       rst,
    input  logic       fifo_rx_pop,
    input  logic       rx,           //from PC
    output logic       tx,           //to PC
    output logic [7:0] rx_pop_data,
    output logic       rx_empty
);


    logic w_b_tick;
    logic w_rx_done;
    logic [7:0] w_rx_data, w_fifo_rx_pop_data, w_fifo_tx_pop_data;
    logic w_fifo_tx_full, w_fifo_rx_empty, w_fifo_tx_empty, w_tx_busy;

    assign rx_pop_data = w_fifo_rx_pop_data;
    assign rx_empty = ~w_fifo_rx_empty;

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (w_b_tick),
        .rx     (rx),
        .rx_data(w_rx_data),
        .rx_done(w_rx_done)
    );

    fifo U_FIFO_RX (
        .clk      (clk),
        .rst      (rst),
        .push     (w_rx_done),
        .pop      (fifo_rx_pop),
        .push_data(w_rx_data),
        .pop_data (w_fifo_rx_pop_data),
        .full     (),
        .empty    (w_fifo_rx_empty)
    );

    fifo U_FIFO_TX (
        .clk      (clk),
        .rst      (rst),
        .push     (~w_fifo_rx_empty),
        .pop      (~w_tx_busy),
        .push_data(w_fifo_rx_pop_data),
        .pop_data (w_fifo_tx_pop_data),
        .full     (w_fifo_tx_full),
        .empty    (w_fifo_tx_empty)
    );

    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .start(~w_fifo_tx_empty),
        .tx_data (w_fifo_tx_pop_data),
        .b_tick  (w_b_tick),
        .tx      (tx),
        .tx_busy (w_tx_busy)
    );

    baud_tick_gen U_TICK_GEN (
        .clk   (clk),
        .rst   (rst),
        .b_tick(w_b_tick)
    );

endmodule

module baud_tick_gen (
    input  logic      clk,
    input  logic      rst,
    output logic      b_tick
);

    // 100Mhz -> 9600hz + 16
    parameter F_COUNT = 100_000_000 / (9600 * 16);
    logic [$clog2(F_COUNT)-1:0] counter_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            counter_reg <= 0;
            b_tick <= 1'b0;
        end else begin
            counter_reg <= counter_reg + 1;

            if (counter_reg == F_COUNT - 1) begin
                counter_reg <= 0;
                b_tick <= 1'b1;
            end else begin
                b_tick <= 1'b0;
            end
        end
    end

endmodule
