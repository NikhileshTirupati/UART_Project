module u_xmit_tb;
    parameter WIDTH = 8;
    reg clk;
    reg rst;
    reg xmitH;
    reg [WIDTH-1:0] xmitDataH;
    wire uart_XMIT_dataH;
    wire xmit_doneH;
    integer i;

    u_xmit dut(clk,rst,xmitH,xmitDataH,uart_XMIT_dataH,xmit_doneH);

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        xmitH=0;
        rst=0;
        xmitDataH = 8'h76;
        @(posedge clk);
        rst=1;
        @(posedge clk);
        xmitH=1;
        @(posedge clk);
        xmitH=0;
        for(i=1;i<(16*12);i=i+1) begin
            @(posedge clk);
        end
    end
endmodule