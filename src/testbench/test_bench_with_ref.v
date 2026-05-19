`timescale 1ns/1ps
`default_nettype none

// =============================================================================
//  UART Testbench  -  10 test cases, XSIM-compatible
//
//  All fork/join_none and wait fork removed.
//  Parallelism replaced with sequential timing calculations.
//
//  Reference model is purely behavioral tasks/functions (unsynthesizable):
//    ref_frame()       - expected 10-bit serial frame for a payload
//    ref_rec_data()    - expected rec_dataH after receiving a payload
//    ref_drive_frame() - clocks bits onto uart_REC_dataH at baud rate
//    ref_sample_frame()- samples uart_XMIT_dataH mid-bit for all 10 bits
//    ref_check_frame() - compares sampled bits to expected, prints PASS/FAIL
//
//  Timing anchored to posedge uart_clk_out (the DUT's exposed baud clock)
//  so the model stays cycle-exact regardless of sys_clk frequency.
// =============================================================================

module uart_tb;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
localparam integer XTAL         = 100_000_000;
localparam integer BAUD         = 2400;
localparam integer WIDTH        = 8;

// CLK_DIV = XTAL / (BAUD * 16 * 2) - mirrors u_baud exactly
localparam integer CLK_DIV      = XTAL / (BAUD * 16 * 2); // 1302
// uart_clk period in ns (sys_clk = 10 ns)
localparam integer UCLK_HALF_NS = CLK_DIV * 10;            // 13020 ns
localparam integer UCLK_FULL_NS = UCLK_HALF_NS * 2;        // 26040 ns
// 1 baud = 16 uart_clk cycles
localparam integer BAUD_UCLKS   = 16;
// Full 10-bit frame = 160 uart_clk cycles
localparam integer FRAME_UCLKS  = (WIDTH + 2) * BAUD_UCLKS;

// ---------------------------------------------------------------------------
// DUT signals
// ---------------------------------------------------------------------------
reg              sys_clk;
reg              sys_rst_l;
reg              xmit_H;
reg  [WIDTH-1:0] xmit_dataH;
reg              uart_REC_dataH;

wire             uart_XMIT_dataH;
wire             xmit_doneH;
wire             xmit_active;
wire [WIDTH-1:0] rec_dataH;
wire             rec_readyH;
wire             rec_busy;
wire             uart_clk_out;

// ---------------------------------------------------------------------------
// DUT
// ---------------------------------------------------------------------------
uart_top #(.SYS_CLK_FREQ(XTAL), .BAUD_RATE(BAUD)) dut (
    .sys_clk        (sys_clk),
    .sys_rst_l      (sys_rst_l),
    .xmitH         (xmit_H),
    .xmit_dataH     (xmit_dataH),
    .uart_REC_dataH (uart_REC_dataH),
    .uart_XMIT_dataH (uart_XMIT_dataH),
    .xmit_doneH     (xmit_doneH),
    .xmit_active    (xmit_active),
    .rec_dataH      (rec_dataH),
    .rec_readyH     (rec_readyH),
    .rec_busy       (rec_busy),
    .uart_clk_1     (uart_clk_out)
);

// ---------------------------------------------------------------------------
// 100 MHz clock
// ---------------------------------------------------------------------------
initial sys_clk = 1'b0;
always  #5 sys_clk = ~sys_clk;

// ---------------------------------------------------------------------------
// Scorecard
// ---------------------------------------------------------------------------
integer pass_cnt;
integer fail_cnt;

// ---------------------------------------------------------------------------
// Loop variable (declared at module level for Verilog-2001 compatibility)
// ---------------------------------------------------------------------------
integer k;
integer t;

// ---------------------------------------------------------------------------
// Shared snapshot registers
// ---------------------------------------------------------------------------
reg [9:0]        sampled_f1;
reg [9:0]        sampled_f2;
reg [WIDTH-1:0]  snap_rec;
reg              snap_ready;
reg              snap_busy;
reg              mid_active;
reg              mid_done;

// ===========================================================================
//  REFERENCE MODEL - behavioral, unsynthesizable
// ===========================================================================

// ---------------------------------------------------------------------------
// ref_frame : build the expected 10-bit serial frame
//   [0]     = start bit (0)
//   [1..8]  = D0..D7 (LSB first)
//   [9]     = stop bit (1)
// ---------------------------------------------------------------------------
function [9:0] ref_frame;
    input [WIDTH-1:0] payload;
    integer i;
    begin
        ref_frame[0] = 1'b0;
        for (i = 0; i < WIDTH; i = i + 1)
            ref_frame[i+1] = payload[i];
        ref_frame[WIDTH+1] = 1'b1;
    end
endfunction

// ---------------------------------------------------------------------------
// ref_rec_data : expected rec_dataH after receiving payload
//   LSB-first TX + right-shift RX = identity
// ---------------------------------------------------------------------------
function [WIDTH-1:0] ref_rec_data;
    input [WIDTH-1:0] payload;
    begin
        ref_rec_data = payload;
    end
endfunction

// ---------------------------------------------------------------------------
// wait_uart_clk : advance n rising edges of uart_clk_out
// ---------------------------------------------------------------------------
task wait_uart_clk;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge uart_clk_out);
    end
endtask

// ---------------------------------------------------------------------------
// apply_reset
// ---------------------------------------------------------------------------
task apply_reset;
    begin
        sys_rst_l      = 1'b0;
        xmit_H         = 1'b0;
        xmit_dataH     = {WIDTH{1'b0}};
        uart_REC_dataH = 1'b1;
        // Hold reset for several uart_clk cycles
        @(posedge sys_clk); #1;
        sys_rst_l = 1'b1;
        wait_uart_clk(4);
    end
endtask

// ---------------------------------------------------------------------------
// ref_drive_frame : clock payload bits onto uart_REC_dataH
//   include_stop = 0 forces stop bit low (FID 6)
// ---------------------------------------------------------------------------
task ref_drive_frame;
    input [WIDTH-1:0] payload;
    input             include_stop;
    reg  [9:0]        frame;
    integer           b;
    begin
        frame = ref_frame(payload);
        for (b = 0; b < WIDTH + 2; b = b + 1) begin
            if (b == WIDTH + 1 && !include_stop)
                uart_REC_dataH = 1'b0;
            else
                uart_REC_dataH = frame[b];
            wait_uart_clk(BAUD_UCLKS);
        end
        uart_REC_dataH = 1'b1;  // idle
    end
endtask

// ---------------------------------------------------------------------------
// ref_sample_frame : sample uart_XMIT_dataH mid-bit for all 10 bits
//   Waits for start bit (negedge), then samples at mid-baud each bit.
// ---------------------------------------------------------------------------
task ref_sample_frame;
    output reg [9:0] sampled;
    integer b;
    begin
        // Wait for start bit
        @(negedge uart_XMIT_dataH);
        // Advance to mid-bit of start bit (8 uart_clk into the 16-clk baud period)
        wait_uart_clk(8);
        // Sample all 10 bits
        for (b = 0; b < WIDTH + 2; b = b + 1) begin
            sampled[b] = uart_XMIT_dataH;
            if (b < WIDTH + 1)
                wait_uart_clk(BAUD_UCLKS);
        end
    end
endtask

// ---------------------------------------------------------------------------
// ref_check_frame : compare sampled[9:0] against ref_frame(payload)
// ---------------------------------------------------------------------------
task ref_check_frame;
    input [32*8-1:0]  test_name;
    input [9:0]       sampled;
    input [WIDTH-1:0] payload;
    reg  [9:0]        expected;
    reg               data_ok;
    begin
        expected = ref_frame(payload);
        data_ok  = 1'b1;

        // Start bit
        if (sampled[0] === expected[0]) begin
            $display("  [PASS] %-28s | start bit = %b", test_name, sampled[0]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %-28s | start bit: got=%b exp=%b",
                     test_name, sampled[0], expected[0]);
            fail_cnt = fail_cnt + 1;
        end

        // Data bits D0..D7
        for (k = 1; k <= WIDTH; k = k + 1) begin
            if (sampled[k] !== expected[k]) begin
                $display("  [FAIL] %-28s | D%0d: got=%b exp=%b",
                         test_name, k-1, sampled[k], expected[k]);
                fail_cnt = fail_cnt + 1;
                data_ok = 1'b0;
            end
        end
        if (data_ok) begin
            $display("  [PASS] %-28s | data bits = 0x%02h (correct)",
                     test_name, payload);
            pass_cnt = pass_cnt + 1;
        end

        // Stop bit
        if (sampled[9] === expected[9]) begin
            $display("  [PASS] %-28s | stop bit  = %b", test_name, sampled[9]);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %-28s | stop bit: got=%b exp=%b",
                     test_name, sampled[9], expected[9]);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// wait_xmit_done : block until xmit_doneH == 1 (with timeout)
// ---------------------------------------------------------------------------
task wait_xmit_done;
    input integer timeout_uclks;
    begin
        t = 0;
        while (xmit_doneH !== 1'b1 && t < timeout_uclks) begin
            @(posedge uart_clk_out);
            t = t + 1;
        end
        if (t >= timeout_uclks)
            $display("  [WARN] wait_xmit_done timed out after %0d clks", t);
    end
endtask

// ---------------------------------------------------------------------------
// wait_rec_ready : block until reception completes (rec_readyH re-asserts)
// ---------------------------------------------------------------------------
task wait_rec_ready;
    input integer timeout_uclks;
    begin
        t = 0;
        // Wait for busy
        while (rec_busy !== 1'b1 && t < timeout_uclks) begin
            @(posedge uart_clk_out); t = t + 1;
        end
        // Wait for ready
        while (rec_readyH !== 1'b1 && t < timeout_uclks) begin
            @(posedge uart_clk_out); t = t + 1;
        end
        if (t >= timeout_uclks)
            $display("  [WARN] wait_rec_ready timed out after %0d clks", t);
        wait_uart_clk(2);   // let registered outputs settle
    end
endtask

// ---------------------------------------------------------------------------
// check_bit / check_bus : one-line pass/fail helpers
// ---------------------------------------------------------------------------
task check_bit;
    input [32*8-1:0] test_name;
    input            got;
    input            exp;
    input [64*8-1:0] msg;
    begin
        if (got === exp) begin
            $display("  [PASS] %-28s | %0s", test_name, msg);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %-28s | %0s  got=%b exp=%b",
                     test_name, msg, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

task check_bus;
    input [32*8-1:0]  test_name;
    input [WIDTH-1:0] got;
    input [WIDTH-1:0] exp;
    input [64*8-1:0]  msg;
    begin
        if (got === exp) begin
            $display("  [PASS] %-28s | %0s  value=0x%02h", test_name, msg, got);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] %-28s | %0s  got=0x%02h exp=0x%02h",
                     test_name, msg, got, exp);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

// ===========================================================================
//  MAIN TEST SEQUENCE  (single initial block, no fork/join_none, no wait fork)
// ===========================================================================
initial begin
    pass_cnt = 0; fail_cnt = 0;

    $dumpfile("uart_tb.vcd");
    $dumpvars(0, uart_tb);

    $display("");
    $display("=================================================================");
    $display("  UART Verification Suite");
    $display("  XTAL=%0d  BAUD=%0d  WIDTH=%0d  CLK_DIV=%0d",
             XTAL, BAUD, WIDTH, CLK_DIV);
    $display("  uart_clk period = %0d ns  |  1 baud = %0d uart_clks",
             UCLK_FULL_NS, BAUD_UCLKS);
    $display("=================================================================");

    // =========================================================================
    // FID 1  xmit_data
    // -------------------------------------------------------------------------
    // Stimulus : xmit_dataH=0x76, xmitH high for one uart_clk edge.
    // Ref model: frame = {stop=1, D7..D0=01110110, start=0}
    //            on wire: 0, 0,1,1,0,1,1,1,0, 1
    // Check    : every bit sampled at mid-baud matches ref_frame(0x76).
    // =========================================================================
    $display("\n--- FID 1: xmit_data ---");
    apply_reset;
    
    @(negedge uart_clk_out); #1;
    xmit_dataH = 8'h76;
    xmit_H     = 1'b1;
    // ref_sample_frame blocks until the entire frame is captured
    ref_sample_frame(sampled_f1);
    @(posedge uart_clk_out); #1;
    xmit_H = 1'b0;

    ref_check_frame("xmit_data", sampled_f1, 8'h76);
    
    //@(posedge xmit_doneH);
    wait_xmit_done(300);
    wait_uart_clk(32);

    // =========================================================================
    // FID 2  xmit_data_cont
    // -------------------------------------------------------------------------
    // Stimulus : start 0x76, then after 9 baud periods (all data bits sent,
    //            stop bit in progress) assert xmitH with data=0xAA.
    //            RTL DONE state sees xmitH==1 and immediately re-arms TXMIT.
    // Ref model: frame1 = ref_frame(0x76), frame2 = ref_frame(0xAA).
    //
    // No fork needed: ref_sample_frame watches uart_XMIT_dataH passively.
    // We start sampling frame1 first (it blocks on negedge start bit),
    // then arm frame2 while frame1 is still being sampled - BUT since
    // ref_sample_frame is blocking we cannot interleave in a single thread.
    //
    // Solution: sample frame1 fully, then immediately call ref_sample_frame
    // for frame2 (which will catch the second negedge).  The xmitH re-arm
    // is driven before we call the second sampler by pre-calculating when
    // to assert it: 9 baud periods after the transmitter starts.
    //
    // We use a non-blocking-assignment trick: drive xmit_H via a delayed
    // absolute-time assignment so it fires during frame1 sampling.
    // =========================================================================
    $display("\n--- FID 2: xmit_data_cont ---");
    apply_reset;

    // Start frame 1
    @(negedge uart_clk_out); #1;
    xmit_dataH = 8'h76;
    xmit_H     = 1'b1;
    

    // We need to re-assert xmitH 9 baud periods (144 uart_clk edges) after
    // the transmitter starts.  ref_sample_frame is busy sampling frame1 at
    // that moment, so we schedule the assertion using a second always block
    // that is enabled by a flag.
    // ---- use a one-shot register + always block (declared after this block) ----
    // Simple approach without fork: count elapsed uart_clk edges inside
    // ref_sample_frame by hooking into the known timing.
    //
    // Actual approach: step through ref_sample_frame manually here so we can
    // interleave the xmitH stimulus at the right uart_clk count.

    // ---------- manual inline frame1 sampling + mid-frame xmitH arm ----------
    // Wait for start bit
    @(negedge uart_XMIT_dataH);
    wait_uart_clk(8);                    // mid-bit of start
    sampled_f1[0] = uart_XMIT_dataH;    // start bit sample

    // Sample D0..D6  (7 data bits = 7 baud periods)
    begin : fid2_data_loop
        integer b2;
        for (b2 = 1; b2 <= 7; b2 = b2 + 1) begin
            wait_uart_clk(BAUD_UCLKS);
            sampled_f1[b2] = uart_XMIT_dataH;
        end
    end
    
    @(posedge uart_clk_out); #1;
    xmit_H = 1'b0;

    // After 8 baud periods total (start + D0..D6) arm the second frame.
    // The transmitter is now on D7 (bit index 8 in the frame).
    // Assert xmitH here so when the FSM reaches DONE (after stop bit)
    // it sees xmitH == 1 and re-arms immediately.
    xmit_dataH = 8'hAA;
    xmit_H     = 1'b1;

    // Sample D7
    wait_uart_clk(BAUD_UCLKS);
    sampled_f1[8] = uart_XMIT_dataH;

    // Sample stop bit
    wait_uart_clk(BAUD_UCLKS);
    sampled_f1[9] = uart_XMIT_dataH;

    // De-assert xmitH after the DONE state has had a chance to latch it
     // Sample frame 2 using the standard helper
    ref_sample_frame(sampled_f2);
    ref_check_frame("xmit_data_cont_frame2", sampled_f2, 8'hAA);
    wait_uart_clk(BAUD_UCLKS);
    xmit_H = 1'b0;

    // Check frame 1
    ref_check_frame("xmit_data_cont_frame1", sampled_f1, 8'h76);

   
    
    wait_xmit_done(300);
    wait_uart_clk(32);

    // =========================================================================
    // FID 3  xmit_data_high_between
    // -------------------------------------------------------------------------
    // Stimulus : start 0x76, de-assert xmitH after one edge.
    //            Re-assert xmitH for one edge at bit 4 of the frame (mid-frame).
    //            The TXMIT state does not check xmitH, so the frame must be
    //            completely undisturbed.
    // Ref model: sampled frame must equal ref_frame(0x76).
    //
    // Same interleaving strategy as FID 2 but we pulse xmitH mid-frame
    // instead of at the end.
    // =========================================================================
    $display("\n--- FID 3: xmit_data_high_between ---");
    apply_reset;
    
    @(negedge uart_clk_out); #1;
    xmit_dataH = 8'h76;
    xmit_H     = 1'b1;
    @(posedge uart_clk_out); #1;
    xmit_H = 1'b0;

    // Inline frame sampling with mid-frame xmitH pulse at bit index 4
    wait_uart_clk(8);
    sampled_f1[0] = uart_XMIT_dataH;   // start

    begin : fid3_loop
        integer b3;
        for (b3 = 1; b3 <= WIDTH + 1; b3 = b3 + 1) begin
            wait_uart_clk(BAUD_UCLKS);
            sampled_f1[b3] = uart_XMIT_dataH;
            // Pulse xmitH for one edge at bit index 4 (D3)
            if (b3 == 4) begin
                @(negedge uart_clk_out); #1;
                xmit_H = 1'b1;
                @(posedge uart_clk_out);
                @(posedge uart_clk_out); #1;
                xmit_H = 1'b0;
            end
        end
    end

    ref_check_frame("xmit_data_high_between", sampled_f1, 8'h76);
    
    //@(posedge xmit_doneH);
    wait_xmit_done(300);
    wait_uart_clk(32);

    // =========================================================================
    // FID 4  rec_data
    // -------------------------------------------------------------------------
    // Stimulus : drive uart_REC_dataH with a valid 0x76 frame.
    //            Transmitter idle.
    // Ref model: ref_rec_data(0x76) = 0x76.
    // Check    : rec_dataH == 0x76, rec_readyH == 1, rec_busy == 0.
    // =========================================================================
    $display("\n--- FID 4: rec_data ---");
    apply_reset;
        
    @(negedge uart_clk_out); #1;
    xmit_H = 1'b0;
    ref_drive_frame(8'h76, 1'b1);
    wait_rec_ready(400);

    check_bus("rec_data", rec_dataH,  ref_rec_data(8'h76), "rec_dataH == 0x76");
    check_bit("rec_data", rec_readyH, 1'b1, "rec_readyH == 1");
    check_bit("rec_data", rec_busy,   1'b0, "rec_busy   == 0");

    
    wait_uart_clk(32);

    // =========================================================================
    // FID 5  rec_data_cont
    // -------------------------------------------------------------------------
    // Stimulus : drive two consecutive frames: 0x76 then 0xAA.
    // Ref model: after frame1 rec_dataH=0x76; after frame2 rec_dataH=0xAA.
    // =========================================================================
    $display("\n--- FID 5: rec_data_cont ---");
    apply_reset;

    xmit_H = 1'b0;

    ref_drive_frame(8'h76, 1'b1);
    wait_rec_ready(400);
    check_bus("rec_data_cont", rec_dataH,  ref_rec_data(8'h76), "frame1: rec_dataH == 0x76");
    check_bit("rec_data_cont", rec_readyH, 1'b1, "frame1: rec_readyH == 1");

    wait_uart_clk(BAUD_UCLKS * 2);   // brief idle gap

    ref_drive_frame(8'hAA, 1'b1);
    wait_rec_ready(400);
    check_bus("rec_data_cont", rec_dataH,  ref_rec_data(8'hAA), "frame2: rec_dataH == 0xAA");
    check_bit("rec_data_cont", rec_readyH, 1'b1, "frame2: rec_readyH == 1");

    wait_uart_clk(32);

    // =========================================================================
    // FID 6  rec_data_no_stop
    // -------------------------------------------------------------------------
    // Stimulus : receive valid 0x76 (baseline), then receive 0xAA with stop
    //            bit forced low.
    // Ref model: RTL DONE state only latches when uart_REC_dataH==1 && counter==15.
    //            With stop=0 → silent return to IDLE, rec_dataH unchanged.
    // Check    : rec_dataH still 0x76 after the corrupted frame.
    // =========================================================================
    $display("\n--- FID 6: rec_data_no_stop ---");
    apply_reset;

    xmit_H = 1'b0;

    ref_drive_frame(8'h76, 1'b1);
    wait_rec_ready(400);
    snap_rec = rec_dataH;   // baseline = 0x76

    wait_uart_clk(BAUD_UCLKS * 2);

    ref_drive_frame(8'hAA, 1'b0);     // stop bit = 0
    wait_uart_clk(BAUD_UCLKS * 4);    // settle time

    check_bus("rec_data_no_stop", rec_dataH, snap_rec,
              "rec_dataH unchanged after missing stop (0x76)");

    wait_uart_clk(32);

    // =========================================================================
    // FID 7  false_start_bit
    // -------------------------------------------------------------------------
    // Stimulus : receive valid 0x55 to set baseline.  Then pull
    //            uart_REC_dataH low for exactly 3 uart_clk cycles and
    //            return high.  The IDLE state needs counter==7 while line is
    //            low; a 3-cycle pulse has a very low chance of satisfying that
    //            and must not trigger a reception.
    //            Wait FRAME_UCLKS + margin to confirm nothing happened.
    // Ref model: rec_dataH and rec_readyH unchanged.
    // =========================================================================
    $display("\n--- FID 7: false_start_bit ---");
    apply_reset;

    xmit_H = 1'b0;

    ref_drive_frame(8'h55, 1'b1);
    wait_rec_ready(400);
    snap_rec   = rec_dataH;    // 0x55
    snap_ready = rec_readyH;   // 1

    wait_uart_clk(BAUD_UCLKS * 2);

    // Inject 3-cycle low pulse
    uart_REC_dataH = 1'b0;
    wait_uart_clk(3);
    uart_REC_dataH = 1'b1;

    // Wait long enough for a phantom frame to complete (if it started)
    wait_uart_clk(FRAME_UCLKS + BAUD_UCLKS * 4);

    check_bus("false_start_bit", rec_dataH,  snap_rec,
              "rec_dataH unchanged after 3-cycle glitch (0x55)");
    check_bit("false_start_bit", rec_readyH, 1'b1,
              "rec_readyH == 1 (receiver stayed IDLE)");
    check_bit("false_start_bit", rec_busy,   1'b0,
              "rec_busy   == 0 (receiver stayed IDLE)");

    wait_uart_clk(32);

    // =========================================================================
    // FID 8  xmit_flag_check
    // -------------------------------------------------------------------------
    // Stimulus : transmit 0xA5.
    // Check mid-frame (after 3 baud periods):
    //   xmit_active == 1, xmit_doneH == 0
    // Check at completion:
    //   xmit_doneH  == 1, xmit_active == 0
    // =========================================================================
    $display("\n--- FID 8: xmit_flag_check ---");
    apply_reset;

    xmit_dataH = 8'hA5;
    xmit_H     = 1'b1;
    @(posedge uart_clk_out); #1;
    xmit_H = 1'b0;

    // Wait 3 baud periods into the frame, sample flags
    wait_uart_clk(3 * BAUD_UCLKS);
    mid_active = xmit_active;
    mid_done   = xmit_doneH;

    check_bit("xmit_flag_check", mid_active, 1'b1,
              "xmit_active == 1 during TX");
    check_bit("xmit_flag_check", mid_done,   1'b0,
              "xmit_doneH  == 0 during TX");

    wait_xmit_done(300);

    check_bit("xmit_flag_check", xmit_doneH,  1'b1,
              "xmit_doneH  == 1 at end of TX");
    check_bit("xmit_flag_check", xmit_active, 1'b0,
              "xmit_active == 0 at end of TX");

    wait_uart_clk(32);

    // =========================================================================
    // FID 9  rec_flag_check
    // -------------------------------------------------------------------------
    // Stimulus : drive a valid 0xC3 frame.
    // Check mid-reception:
    //   rec_readyH == 0, rec_busy == 1
    // Check after reception:
    //   rec_readyH == 1, rec_busy == 0
    //
    // No fork: drive the first few bits manually, sample flags, then drive
    // the remaining bits and call wait_rec_ready.
    // =========================================================================
    $display("\n--- FID 9: rec_flag_check ---");
    apply_reset;

    xmit_H = 1'b0;

    // Drive frame start + 3 data bits manually to create the mid-reception window
    begin : fid9_partial
        reg [9:0] frame9;
        integer   b9;
        frame9 = ref_frame(8'hC3);

        // Send start + D0..D2  (4 bits = 4 baud periods)
        for (b9 = 0; b9 <= 3; b9 = b9 + 1) begin
            uart_REC_dataH = frame9[b9];
            wait_uart_clk(BAUD_UCLKS);
        end

        // Sample flags mid-reception
        check_bit("rec_flag_check", rec_readyH, 1'b0,
                  "rec_readyH == 0 during reception");
        check_bit("rec_flag_check", rec_busy,   1'b1,
                  "rec_busy   == 1 during reception");

        // Drive remaining bits  D3..D7 + stop
        for (b9 = 4; b9 <= WIDTH + 1; b9 = b9 + 1) begin
            uart_REC_dataH = frame9[b9];
            wait_uart_clk(BAUD_UCLKS);
        end
        uart_REC_dataH = 1'b1;   // idle
    end

    wait_rec_ready(400);

    check_bit("rec_flag_check", rec_readyH, 1'b1,
              "rec_readyH == 1 after reception");
    check_bit("rec_flag_check", rec_busy,   1'b0,
              "rec_busy   == 0 after reception");

    wait_uart_clk(32);

    // =========================================================================
    // FID 10  hold_check
    // -------------------------------------------------------------------------
    // Stimulus : transmit 0xB4 (TX path) and simultaneously receive 0xB4
    //            (RX path via uart_REC_dataH).  After both complete, apply
    //            no stimulus for 5 baud periods.
    // Ref model: all outputs must hold their post-completion values.
    //   uart_XMIT_dataH = 1  (idle high)
    //   rec_dataH       = 0xB4
    //   rec_readyH      = 1
    //   rec_busy        = 0
    //
    // No fork: TX takes 160 uart_clk cycles; drive RX frame in lockstep
    // by starting RX immediately after TX starts (they share the same
    // baud clock so their timing is aligned).
    //
    // Strategy: start TX, then drive the RX frame sequentially.
    // TX runs autonomously; RX is driven bit-by-bit matching the baud cadence.
    // Both finish within FRAME_UCLKS cycles.
    // =========================================================================
    $display("\n--- FID 10: hold_check ---");
    apply_reset;

    // Kick off transmitter
    xmit_dataH = 8'hB4;
    xmit_H     = 1'b1;
    @(posedge uart_clk_out); #1;
    xmit_H = 1'b0;

    // Drive receiver frame sequentially (TX runs in the background on its own)
    ref_drive_frame(8'hB4, 1'b1);

    // Wait for transmitter to finish (it started 1 uart_clk before RX frame)
    wait_xmit_done(300);
    // Wait for receiver to finish
    wait_rec_ready(400);
    wait_uart_clk(8);   // let registered outputs settle

    // Snapshot
    snap_rec   = rec_dataH;
    snap_ready = rec_readyH;

    // 5 idle baud periods, zero stimulus
    wait_uart_clk(5 * BAUD_UCLKS);

    check_bus("hold_check", rec_dataH,       snap_rec,
              "rec_dataH stable for 5 idle baud periods");
    check_bit("hold_check", rec_readyH,      snap_ready,
              "rec_readyH stable for 5 idle baud periods");
    check_bit("hold_check", uart_XMIT_dataH, 1'b1,
              "uart_XMIT_dataH == 1 (idle) after TX done");
    check_bit("hold_check", rec_readyH,      1'b1,
              "rec_readyH == 1 in idle");
    check_bit("hold_check", rec_busy,        1'b0,
              "rec_busy   == 0 in idle");
    check_bus("hold_check", rec_dataH, ref_rec_data(8'hB4),
              "rec_dataH == 0xB4 held correctly");

    // =========================================================================
    // Summary
    // =========================================================================
    wait_uart_clk(16);
    $display("");
    $display("=================================================================");
    $display("  SUMMARY  |  PASS: %0d  |  FAIL: %0d  |  TOTAL: %0d",
             pass_cnt, fail_cnt, pass_cnt + fail_cnt);
    if (fail_cnt == 0)
        $display("  STATUS  : ALL TESTS PASSED");
    else
        $display("  STATUS  : SOME TESTS FAILED  (see [FAIL] lines above)");
    $display("=================================================================");
    $display("");

    $finish;
end

endmodule

`timescale 1ns/1ps
`default_nettype none
module transmitter(
    input  wire       baud_clk_16x,
    input  wire       sys_rst_l,
    input  wire       xmitH,
    input  wire [7:0] xmit_dataH,
    output reg        uart_XMIT_dataH,
    output reg        xmit_doneH,
    output reg        xmit_active
);
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;
    reg [1:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] tx_data;
    always @(posedge baud_clk_16x or negedge sys_rst_l) begin
        if(!sys_rst_l) begin
            state           <= IDLE;
            uart_XMIT_dataH <= 1'b1;
            xmit_doneH      <= 1'b1;
            xmit_active     <= 1'b0;
            tick_cnt        <= 0;
            bit_cnt         <= 0;
            tx_data         <= 0;
        end
        else begin
            case(state)
                IDLE: begin
                    uart_XMIT_dataH <= 1'b1;
                    xmit_active     <= 1'b0;
                    tick_cnt        <= 0;
                    bit_cnt         <= 0;
                    xmit_doneH <= 1'b1;
                    if(xmitH) begin
                        tx_data     <= xmit_dataH;
                        state       <= START;
                        xmit_doneH <= 1'b0;
                        xmit_active <= 1'b1;
                    end
                end
                START: begin
                    uart_XMIT_dataH <= 1'b0;
                    xmit_doneH <= 1'b0;
                    if(tick_cnt == 15) begin
                        tick_cnt <= 0;
                        state    <= DATA;
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                DATA: begin
                    uart_XMIT_dataH <= tx_data[bit_cnt];
                    xmit_doneH <= 1'b0;
                    if(tick_cnt == 15) begin
                        tick_cnt <= 0;
 
                        if(bit_cnt == 7) begin
                            bit_cnt <= 0;
                            state   <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                STOP: begin
                    uart_XMIT_dataH <= 1'b1;
                    xmit_doneH <= 1'b0;
                    if(tick_cnt == 15) begin
                        tick_cnt    <= 0;
                        state       <= IDLE;
                        xmit_active <= 1'b0;
                        xmit_doneH  <= 1'b1;
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
`default_nettype none
module receiver(
    input  wire       baud_clk_16x,
    input  wire       sys_rst_l,
    input  wire       uart_REC_dataH,
    output reg [7:0]  rec_dataH,
    output reg        rec_readyH,
    output reg        rec_busy
);
    reg sync1, sync2;
    always @(posedge baud_clk_16x or negedge sys_rst_l) begin
        if(!sys_rst_l) begin
            sync1 <= 1'b1;
            sync2 <= 1'b1;
        end
        else begin
            sync1 <= uart_REC_dataH;
            sync2 <= sync1;
        end
    end
    wire rx_data = sync2;
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;
    reg [1:0] state;
    reg [3:0] tick_cnt;
    reg [2:0] bit_cnt;
    reg [7:0] rx_shift;
    always @(posedge baud_clk_16x or negedge sys_rst_l) begin
        if(!sys_rst_l) begin
            state      <= IDLE;
            rec_dataH  <= 8'd0;
            rec_readyH <= 1'b1;
            rec_busy   <= 1'b0;
            tick_cnt   <= 0;
            bit_cnt    <= 0;
            rx_shift   <= 0;
        end
        else begin
            case(state)
                IDLE: begin
                    rec_busy <= 1'b0;
                    tick_cnt <= 0;
                      rec_readyH <= 1'b1;
                    bit_cnt  <= 0;
                    if(rx_data == 1'b0) begin
                        state    <= START;
                        rec_busy <= 1'b1;
                    end
                end
                START: begin
                  rec_readyH <= 1'b0;
                    if(tick_cnt == 7) begin
                        tick_cnt <= 0;
 
                        if(rx_data == 1'b0)
                            state <= DATA;
                        else
                            state <= IDLE;
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                DATA: begin
                  rec_readyH <= 1'b0;
                    if(tick_cnt == 15) begin
                        tick_cnt <= 0;
 
                        rx_shift[bit_cnt] <= rx_data;
                        if(bit_cnt == 7) begin
                            bit_cnt <= 0;
                            state   <= STOP;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                STOP: begin
                  rec_readyH <= 1'b0;
                    if(tick_cnt == 15) begin
                        tick_cnt <= 0;
                        state    <= IDLE;
                        rec_busy <= 1'b0;
 
                        if(rx_data == 1'b1) begin
                            rec_dataH  <= rx_shift;
                            rec_readyH <= 1'b1;
                        end
                    end
                    else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

`timescale 1ns/1ps
`default_nettype none
module baud_gen #(
    parameter integer SYS_CLK_FREQ = 50000000,
    parameter integer BAUD_RATE    = 9600
)(
    input  wire sys_clk,
    input  wire sys_rst_l,
    output reg  baud_clk_16x
);
    localparam integer DIV = SYS_CLK_FREQ / (BAUD_RATE * 16 * 2);
    reg [$clog2(DIV)-1:0] count;
    always @(posedge sys_clk or negedge sys_rst_l) begin
        if(!sys_rst_l) begin
            count        <= 0;
            baud_clk_16x <= 1'b0;
        end
        else begin
            if(count == DIV-1) begin
                count        <= 0;
                baud_clk_16x <= ~baud_clk_16x;  
            end
            else begin
                count <= count + 1;
            end
        end
    end
endmodule

`timescale 1ns/1ps
`default_nettype none
module uart_top #(
    parameter integer SYS_CLK_FREQ = 50000000,
    parameter integer BAUD_RATE    = 9600
)(
    input  wire       sys_clk,
    input  wire       sys_rst_l,
    input  wire       xmitH,
    input  wire [7:0] xmit_dataH,
    output wire       uart_XMIT_dataH,
    output wire       xmit_doneH,
    output wire       xmit_active,
 
    input  wire       uart_REC_dataH,
    output wire [7:0] rec_dataH,
    output wire       rec_readyH,
    output wire       rec_busy,
    output wire       uart_clk_1
);
    wire baud_clk_16x;
    baud_gen #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) bg (
        .sys_clk(sys_clk),
        .sys_rst_l(sys_rst_l),
        .baud_clk_16x(baud_clk_16x)
    );
 
    transmitter tx (
        .baud_clk_16x(baud_clk_16x),
        .sys_rst_l(sys_rst_l),
        .xmitH(xmitH),
        .xmit_dataH(xmit_dataH),
        .uart_XMIT_dataH(uart_XMIT_dataH),
        .xmit_doneH(xmit_doneH),
        .xmit_active(xmit_active)
    );
    receiver rx (
        .baud_clk_16x(baud_clk_16x),
        .sys_rst_l(sys_rst_l),
        .uart_REC_dataH(uart_REC_dataH),
        .rec_dataH(rec_dataH),
        .rec_readyH(rec_readyH),
        .rec_busy(rec_busy)
    );
    assign uart_clk_1 = baud_clk_16x;
endmodule