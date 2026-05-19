`timescale 1ns / 1ps
`default_nettype none

module uart_tb;
    reg sys_clk;
    reg sys_rst_l;
    reg xmit_H;
    reg [7:0] xmit_dataH;
    //reg uart_REC_dataH;
    wire uart_XMIT_dataH;
    wire xmit_doneH;
    wire [7:0] rec_dataH;
    wire rec_readyH;
    wire rec_busy;
    wire xmit_active;
    wire uart_clk_1;

    uart #(.XTAL(100_000_000), .BAUD(2400), .WIDTH(8)) dut (
        .sys_clk(sys_clk),
        .sys_rst_l(sys_rst_l),
        .xmit_H(xmit_H),
        .uart_REC_dataH(uart_XMIT_dataH),
        .xmit_dataH(xmit_dataH),
        .uart_XMIT_dataH(uart_XMIT_dataH),
        .xmit_active(xmit_active),
        .xmit_doneH(xmit_doneH),
        .rec_dataH(rec_dataH),
        .rec_readyH(rec_readyH),
        .rec_busy(rec_busy),
        .uart_clk_1(uart_clk_1)
    );

    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk; // 100MHz clock
    end

    initial begin
        sys_rst_l = 0;
        xmit_H = 0;
        xmit_dataH = 8'h00;

        #20; // Wait for reset deassertion
        sys_rst_l = 1;

        @(posedge uart_clk_1); // Wait for some time after reset
        xmit_dataH = 8'hA6; // Example data to transmit
        xmit_H = 1; // Start transmission
        @(posedge uart_clk_1);
        xmit_H = 0;
        @(posedge rec_readyH);
        //#500000;
        xmit_dataH = 8'hAA;
        xmit_H = 1;
        repeat(32) @(posedge uart_clk_1);
        xmit_H = 0;
        #2000; // Wait for transmission to complete
        xmit_H = 0;
    end
endmodule