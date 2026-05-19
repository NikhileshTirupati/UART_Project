`timescale 1ns/1ns
module u_baud_tb ();
    reg clk;
    reg rst;
    wire baud_clk;

    u_baud dut(clk,rst,baud_clk);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 0;
        @(posedge clk);
        rst = 1;
        #10000;
    end
endmodule //u_baud_tb