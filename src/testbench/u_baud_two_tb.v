`timescale 1ns / 1ps
`default_nettype none

module uart_tb;
    reg sys_clk_1;
    reg sys_rst_l;
    reg xmit_H_1;
    reg [7:0] xmit_dataH_1;
    //reg uart_REC_dataH;
    wire uart_XMIT_dataH_1;
    wire xmit_doneH_1;
    wire [7:0] rec_dataH_1;
    wire rec_readyH_1;
    wire rec_busy_1;
    wire xmit_active_1;
    wire baud_clk_1_1;
    
    reg sys_clk_2;
    reg sys_rst_2;
    reg xmit_H_2;
    reg [7:0] xmit_dataH_2;
    //reg uart_REC_dataH;
    wire uart_XMIT_dataH_2;
    wire xmit_doneH_2;
    wire [7:0] rec_dataH_2;
    wire rec_readyH_2;
    wire rec_busy_2;
    wire xmit_active_2;
    wire baud_clk_1_2;

    uart #(.XTAL(512), .BAUD(2), .WIDTH(8)) dut0 (
        .sys_clk(sys_clk_1),
        .sys_rst_l(sys_rst_l),
        .xmit_H(xmit_H_1),
        .uart_REC_dataH(uart_XMIT_dataH_1),
        .xmit_dataH(xmit_dataH_1),
        .uart_XMIT_dataH(uart_XMIT_dataH_1),
        .xmit_active(xmit_active_1),
        .xmit_doneH(xmit_doneH_1),
        .rec_dataH(rec_dataH_1),
        .rec_readyH(rec_readyH_1),
        .rec_busy(rec_busy_1),
        .baud_clk_1(baud_clk_1_1)
    );
    
    uart #(.XTAL(256), .BAUD(2), .WIDTH(8)) dut1 (
        .sys_clk(sys_clk_2),
        .sys_rst_l(sys_rst_2),
        .xmit_H(xmit_H_2),
        .uart_REC_dataH(uart_XMIT_dataH_1),
        .xmit_dataH(xmit_dataH_2),
        .uart_XMIT_dataH(uart_XMIT_dataH_2),
        .xmit_active(xmit_active_2),
        .xmit_doneH(xmit_doneH_2),
        .rec_dataH(rec_dataH_2),
        .rec_readyH(rec_readyH_2),
        .rec_busy(rec_busy_2),
        .baud_clk_1(baud_clk_1_2)
    );

    initial begin
        sys_clk_1 = 0;
        forever #5 sys_clk_1 = ~sys_clk_1; // 100MHz clock
    end
    
    initial begin
        sys_clk_2 = 0;
        forever #10 sys_clk_2 = ~sys_clk_2; // 50MHz clock
    end
    initial begin
        sys_rst_l = 0;
        sys_rst_2 = 0;
        xmit_H_1 = 0;
        xmit_dataH_1 = 8'h00;
        #50;
        //@(posedge baud_clk_1_1); // Wait for reset deassertion
        sys_rst_l = 1;
        //@(posedge baud_clk_1_2);
        sys_rst_2 = 1;

         @(negedge baud_clk_1_1); // Wait for some time after reset
        xmit_dataH_1 = 8'hA6; // Example data to transmit
        xmit_H_1 = 1; // Start transmission
         @(posedge baud_clk_1_1);
        xmit_H_1 = 0;
        @(posedge rec_readyH_2);
        //#500000;
        xmit_dataH_1 = 8'hAA;
        xmit_H_1 = 1;
        repeat(32) @(posedge baud_clk_1_1);
        xmit_H_1 = 0;
        #2000; // Wait for transmission to complete
        xmit_H_1 = 0;
    end
endmodule