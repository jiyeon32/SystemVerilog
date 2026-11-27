`timescale 1ns / 1ps

module ascii_decoder (
    input   logic     [7:0] ascii,
    output  logic     [7:0] bin
);

    always_comb begin
        bin = 8'hff;
            case (ascii)
                8'h30: bin = 8'h0;
                8'h31: bin = 8'h1;
                8'h32: bin = 8'h2;
                8'h33: bin = 8'h3;
                8'h34: bin = 8'h4;
                8'h35: bin = 8'h5;
                8'h36: bin = 8'h6;
                8'h37: bin = 8'h7;
                8'h38: bin = 8'h8;
                8'h39: bin = 8'h9;
                8'h41, 8'h61: bin = 8'hA;
                8'h42, 8'h62: bin = 8'hB;
                8'h43, 8'h63: bin = 8'hC;
                8'h44, 8'h64: bin = 8'hD;
                8'h45, 8'h65: bin = 8'hE;
                8'h46, 8'h66: bin = 8'hF; 
            endcase
    end
endmodule
