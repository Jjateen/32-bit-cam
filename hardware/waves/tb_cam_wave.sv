// Walks the CAM through fill, hit, miss and invalidate. Dumps cam_wave.vcd
// (the diagram is generated from it) and prints a per-cycle table as a log.
`timescale 1ns/1ps
module tb_cam_wave;
    localparam int DEPTH = 4, WIDTH = 32, IDXW = $clog2(DEPTH);

    logic            clk = 0, rst_n = 0, we = 0, winvalidate = 0;
    logic [IDXW-1:0] waddr = '0;
    logic [WIDTH-1:0] wdata = '0, search = '0;
    logic            match;
    logic [IDXW-1:0] match_index;
    logic [DEPTH-1:0] match_onehot;

    cam #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (
        .clk, .rst_n, .we, .waddr, .wdata, .winvalidate,
        .search, .match, .match_index, .match_onehot
    );

    always #5 clk = ~clk;

    int cyc = 0;
    string note = "reset";

    always @(posedge clk) begin
        $display("%0d,%0b,%0b,%0d,%08h,%08h,%0b,%0d,%04b,%s",
                 cyc, rst_n, we, waddr, wdata, search,
                 match, match_index, match_onehot, note);
        cyc++;
    end

    task automatic step(input string n); note = n; @(posedge clk); #1; endtask

    initial begin
        // depth 1: Icarus emits $ivl_for_loop scopes for cam.sv's loops, and
        // strict VCD parsers reject the '$' in those scope names
        $dumpfile("cam_wave.vcd");
        $dumpvars(1, tb_cam_wave);

        // held in reset: all entries invalid
        rst_n = 0; search = 32'hDEAD_BEEF;
        step("reset"); step("reset");
        @(negedge clk); rst_n = 1;

        // fill four entries, one per cycle
        @(negedge clk); we = 1; waddr = 0; wdata = 32'hDEAD_BEEF; step("write e0");
        @(negedge clk); we = 1; waddr = 1; wdata = 32'h1234_5678; step("write e1");
        @(negedge clk); we = 1; waddr = 2; wdata = 32'hCAFE_BABE; step("write e2");
        @(negedge clk); we = 1; waddr = 3; wdata = 32'h0000_0001; step("write e3");
        @(negedge clk); we = 0; wdata = '0; waddr = '0;

        // searches: hit e0, hit e2, miss
        search = 32'hDEAD_BEEF; step("hit e0");
        search = 32'hCAFE_BABE; step("hit e2");
        search = 32'hFFFF_FFFF; step("miss");

        // invalidate e2, then the same key misses
        @(negedge clk); we = 1; winvalidate = 1; waddr = 2;
        search = 32'hCAFE_BABE; step("invalidate e2");
        @(negedge clk); we = 0; winvalidate = 0;
        step("now misses");
        step("idle");
        $finish;
    end
endmodule
