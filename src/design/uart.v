module uart #(parameter XTAL = 100_000_000, parameter BAUD = 2400, parameter WIDTH = 8)(
    input  wire sys_clk,
    input  wire sys_rst_l,
    input  wire xmit_H,
    input  wire [WIDTH-1:0] xmit_dataH,
    input  wire uart_REC_dataH,
    output wire uart_XMIT_dataH,
    output wire xmit_doneH,
    output wire [WIDTH-1:0] rec_dataH,
    output wire rec_readyH,
    output wire rec_busy,
    output wire xmit_active,
    output wire uart_clk_1
);
    u_baud #(.XTAL(XTAL), .BAUD(BAUD)) baud_inst (
        .clk(sys_clk),
        .rst(sys_rst_l),
        .uart_clk(uart_clk)
    );

    u_xmit #(.WIDTH(WIDTH)) xmit_inst (
        .clk(uart_clk),
        .rst(sys_rst_l),
        .xmitH(xmit_H),
        .xmitDataH(xmit_dataH),
        .uart_XMIT_dataH(uart_XMIT_dataH),
        .xmit_doneH(xmit_doneH),
        .xmit_active(xmit_active)
    );

    u_rec #(.WIDTH(WIDTH)) rec_inst (
        .clk(uart_clk),
        .rst(sys_rst_l),
        .uart_REC_dataH(uart_REC_dataH),
        .rec_dataH(rec_dataH),
        .rec_readyH(rec_readyH),
        .rec_busy(rec_busy)
    );

    assign uart_clk_1 = uart_clk;
endmodule //uart