module u_rec #(parameter WIDTH=8)(
    input wire clk,
    input wire rst,
    input wire uart_REC_dataH,
    output reg [WIDTH-1:0] rec_dataH,
    output reg rec_readyH,
    output reg rec_busy
);

    localparam IDLE = 2'b00, REC = 2'b01, DONE = 2'b10;
    reg [1:0] cs,ns;
    reg [WIDTH-1:0] data;
    reg [$clog2(WIDTH)+1:0] bit_cnt;
    reg [$clog2(20)-1:0] counter;
 
    reg ready, busy, count;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cs <= IDLE;
            rec_dataH <= 0;
            rec_readyH <= 0;
            rec_busy <= 0;
            counter<=0;
        end
        else begin
            cs <= ns;
            rec_readyH <= ready;
            rec_busy <= busy;
            if (count) counter <= counter + 1;
            else counter <= counter;
        end 
    end

    always @(*) begin
        case (cs)
            IDLE: begin
                bit_cnt = 0;
                ready = 1;
                busy = 0;
                count = 0;
                if (!uart_REC_dataH) begin
                    count = 1;
                    if(counter == 7 && !uart_REC_dataH) begin
                    data = 0;
                    busy = 1;
                    ready = 1'b0;
                    ns = REC;
                    counter = 0;
                    end
                    else ns = IDLE;
                end
                else ns = IDLE;
            end
            REC: begin
                count = 1;
                ready = 1'b0;
                busy = 1;
                if(bit_cnt == 0) begin
                    if(counter == 15) begin
                        counter = 0;
                        data = {uart_REC_dataH,data[WIDTH-1:1]};
                        bit_cnt = bit_cnt+1;
                    end 
                    else ns = REC;
                end
                else if(bit_cnt < WIDTH) begin
                    if(counter == 16) begin
                        counter = 0;
                        data = {uart_REC_dataH,data[WIDTH-1:1]};
                        bit_cnt = bit_cnt + 1;
                        if (bit_cnt < WIDTH) ns = REC;
                        else ns = DONE;
                    end
                    else ns = REC; 
                end
                else ns = DONE;
            end
            DONE: begin
                count = 1;
                if (uart_REC_dataH && counter==15) begin
                    ready = 1'b1;
                    rec_dataH = data;
                    busy = 0;
                    counter = 0;
                    ns = IDLE;
                end
                else if(counter ==15) begin
                    ns = IDLE;
                    counter = 0;
                end
                else ns = DONE;
            end
            default: ns = IDLE;
        endcase
    end
endmodule