// CAM testbench: match/miss, matched index, overwrite, invalidate, duplicate priority.
`timescale 1ns/1ps
module tb_cam;
    localparam int DEPTH = 4, WIDTH = 32, IDXW = $clog2(DEPTH);

    logic            clk = 0, rst_n = 0, we = 0, winvalidate = 0;
    logic [IDXW-1:0] waddr;
    logic [WIDTH-1:0] wdata, search = '0;
    logic            match;
    logic [IDXW-1:0] match_index;
    logic [DEPTH-1:0] match_onehot;

    int checks = 0, errors = 0;

    cam #(.DEPTH(DEPTH), .WIDTH(WIDTH)) dut (
        .clk, .rst_n, .we, .waddr, .wdata, .winvalidate,
        .search, .match, .match_index, .match_onehot
    );

    always #5 clk = ~clk;

    task automatic wr(input [IDXW-1:0] a, input [WIDTH-1:0] d);
        @(negedge clk); we = 1; winvalidate = 0; waddr = a; wdata = d;
        @(negedge clk); we = 0;
    endtask

    task automatic invalidate(input [IDXW-1:0] a);
        @(negedge clk); we = 1; winvalidate = 1; waddr = a;
        @(negedge clk); we = 0;
    endtask

    task automatic chk(input [WIDTH-1:0] key, input exp_m,
                       input [IDXW-1:0] exp_i, input string name);
        search = key; #1; checks++;
        if (match !== exp_m || (exp_m && match_index !== exp_i)) begin
            $display("FAIL  %-26s key=%08h  match=%0b idx=%0d  (exp match=%0b idx=%0d)",
                     name, key, match, match_index, exp_m, exp_i);
            errors++;
        end else begin
            $display("PASS  %-26s key=%08h  match=%0b idx=%0d",
                     name, key, match, match_index);
        end
    endtask

    initial begin
        // reset: everything invalid -> every search misses
        rst_n = 0; repeat (2) @(negedge clk); rst_n = 1;
        chk(32'hAAAA_AAAA, 1'b0, '0, "empty -> miss");

        // fill all four entries
        wr(0, 32'hDEAD_BEEF); wr(1, 32'h1234_5678);
        wr(2, 32'hCAFE_BABE); wr(3, 32'h0000_0001);
        chk(32'hDEAD_BEEF, 1'b1, 2'd0, "hit entry 0");
        chk(32'h1234_5678, 1'b1, 2'd1, "hit entry 1");
        chk(32'hCAFE_BABE, 1'b1, 2'd2, "hit entry 2");
        chk(32'h0000_0001, 1'b1, 2'd3, "hit entry 3");
        chk(32'hFFFF_FFFF, 1'b0, '0,   "unknown key -> miss");

        // overwrite entry 1: old value misses, new value hits
        wr(1, 32'h9999_9999);
        chk(32'h1234_5678, 1'b0, '0,   "old value gone");
        chk(32'h9999_9999, 1'b1, 2'd1, "new value hit");

        // invalidate entry 2
        invalidate(2);
        chk(32'hCAFE_BABE, 1'b0, '0,   "invalidated -> miss");

        // duplicate key in entries 0 and 3 -> lowest index wins
        wr(3, 32'hDEAD_BEEF);
        chk(32'hDEAD_BEEF, 1'b1, 2'd0, "duplicate -> lowest idx");

        $display("\n%0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("ALL PASS"); else $display("FAILED");
        $finish;
    end
endmodule
