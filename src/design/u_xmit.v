module u_xmit #(parameter WIDTH=8)(
    input wire clk,
    input wire rst,
    input wire xmitH,
    input wire [WIDTH-1:0] xmitDataH,
    output reg uart_XMIT_dataH,
    output reg xmit_doneH,
    output reg xmit_active
);

    localparam IDLE = 2'b00, TXMIT = 2'b01, DONE = 2'b10;
    reg [1:0] cs,ns;
    reg [WIDTH+1:0] data;
    reg [$clog2(WIDTH+2)-1:0] bit_cnt;
    reg [4:0] counter;

    reg done;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cs <= IDLE;
            uart_XMIT_dataH <= 1;
        end
        else begin
            cs <= ns;
            uart_XMIT_dataH <= data[0];
            if (cs == TXMIT || cs == DONE) counter <= counter + 1;
        end 
    end

    always @(*) begin
        case (cs)
            IDLE: begin
                bit_cnt = 0;
                xmit_active = 0;
                xmit_doneH = 1'b1;
                data = {(WIDTH+2){1'b1}}; // Idle state is high
                if (xmitH) begin
                    data = {1'b1, xmitDataH, 1'b0}; // Stop bit + Data + Start bit
                    counter = 0;     
                    bit_cnt = 1; 
                    ns = TXMIT;
                end
                else ns = IDLE;
            end
            TXMIT: begin
                xmit_doneH = 1'b0;
                xmit_active = 1;
                if(counter == 16) begin
                    counter = 0;
                    if (bit_cnt < WIDTH + 2) begin
                        data = data >> 1;
                        bit_cnt = bit_cnt + 1;
                    end
                    else begin
                            ns = DONE;
                            xmit_doneH = 1'b1;
                            xmit_active = 0;
                    end
                end
                else ns = TXMIT;
            end
            DONE: begin
                    if (xmitH) begin
                        ns = TXMIT;
                        data = {1'b1, xmitDataH, 1'b0}; // Stop bit + Data + Start bit
                        counter = 0;     
                        bit_cnt = 1;              
                    end
                    else ns = IDLE;
            end
            default: ns = IDLE;
        endcase
    end
endmodule