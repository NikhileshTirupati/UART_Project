module u_baud #(parameter XTAL = 100000000, parameter BAUD = 2400)(
    input  wire clk,
    input  wire rst,
    output reg uart_clk
);

    localparam CLK_DIV = XTAL/(BAUD*16*2);
    reg [$clog2(CLK_DIV)-1:0] counter;
    

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            uart_clk <= 0;
            counter <= 0;
        end
        else begin
            if(counter == CLK_DIV-1) begin
                uart_clk <= ~uart_clk;
                counter <= 0;
            end 
            else
                counter <= counter+1;
        end
    end

endmodule //u_baud