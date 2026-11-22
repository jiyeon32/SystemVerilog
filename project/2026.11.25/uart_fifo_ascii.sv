`timescale 1ns / 1ps

module uart_fifo_ascii (
    input  clk,
    input  rst,
    input  rx,     
    output tx,
    output run_stop,
    output clear,
    output mode
    //output [3:0] fnd_com,
    //output [7:0] fnd_font
);

    wire [7:0] w_rx_pop_data;
    wire [3:0] w_bin;
    wire w_rx_empty, w_rx_pop;

    uart_fifo_loopback U_UART_FIFO_LOOPBACK (
        .clk        (clk),
        .rst        (rst),
        .fifo_rx_pop(w_rx_pop),
        .rx         (rx),            
        .tx         (tx),            
        .rx_pop_data(w_rx_pop_data),
        .rx_empty   (w_rx_empty)
    );

    ascii_decoder U_ASCII_DECODER (
        .clk   (clk),
        .rst   (rst),
        .enable(w_rx_empty),
        .ascii (w_rx_pop_data),
        .pop   (w_rx_pop),
        .run_stop(run_stop),
        .clear(clear),
        .mode(mode)
        //.bin   (w_bin)
    );

    /*fnd_controller U_FND_CNTL (
        .clk     (clk),
        .reset   (rst),
        .fnd_data(w_bin),
        .fnd_com (fnd_com),
        .fnd_font(fnd_font)
    );*/

endmodule
