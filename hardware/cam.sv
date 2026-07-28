// 4-entry, 32-bit Content-Addressable Memory: searched by content, not address.
// Lowest index wins on duplicate keys. Same associative lookup a DFI tag store
// uses to check an address against its protected set in one cycle.
module cam #(
    parameter int DEPTH = 4,
    parameter int WIDTH = 32,
    // $clog2(1) is 0, which would make the index ports [-1:0]; floor at 1 bit
    localparam int IDXW = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
)(
    input  logic            clk,
    input  logic            rst_n,        // active-low async reset

    // write / fill port
    input  logic            we,           // write strobe
    input  logic [IDXW-1:0] waddr,        // entry to write
    input  logic [WIDTH-1:0] wdata,       // value to store
    input  logic            winvalidate,  // with we: clear entry's valid bit

    // search port (combinational)
    input  logic [WIDTH-1:0] search,      // key to look up
    output logic            match,        // any valid entry equals `search`
    output logic [IDXW-1:0] match_index,  // index of the lowest matching entry
    output logic [DEPTH-1:0] match_onehot // per-entry match
);
    logic [WIDTH-1:0] mem   [DEPTH];
    logic             valid [DEPTH];

    // write / invalidate
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i]   <= '0;
                valid[i] <= 1'b0;
            end
        end else if (we) begin
            mem[waddr]   <= wdata;
            valid[waddr] <= ~winvalidate;
        end
    end

    // associative compare
    always_comb begin
        for (int i = 0; i < DEPTH; i++)
            match_onehot[i] = valid[i] && (mem[i] == search);
    end
    assign match = |match_onehot;

    // priority encode: iterate high->low so the lowest set index wins
    always_comb begin
        match_index = '0;
        for (int i = DEPTH-1; i >= 0; i--)
            if (match_onehot[i]) match_index = IDXW'(i);
    end
endmodule
