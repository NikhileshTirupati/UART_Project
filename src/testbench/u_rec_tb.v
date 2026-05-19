module u_rec_tb ();
    reg clk,rst,uart_REC_dataH;
    wire [7:0] rec_dataH;
    wire rec_readyH;
    integer i;

    u_rec dut(clk,rst,uart_REC_dataH,rec_dataH,rec_readyH);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 0;
        uart_REC_dataH = 1;
        @(posedge clk);
        rst = 1;
        uart_REC_dataH = 0;
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 1;
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 0;
        for(i=0;i<32;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 1;
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 0;
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 1;
        for(i=0;i<32;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 0;
        for(i=0;i<32;i=i+1) begin
            @(posedge clk);
        end
        uart_REC_dataH = 1;
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        for(i=0;i<16;i=i+1) begin
            @(posedge clk);
        end
        $finish;
        
    end

endmodule //u_rec_tb