// Self-running CAM demo for the Tang Nano 9K: preloads 4 entries, then cycles
// search keys at ~1 Hz. LED4=match, LED3=miss, LED2=tick, LED1:0=match_index.
// Each result is also reported over UART so the board's output can be captured
// and compared against the simulation.
module cam_fpga_top #(
    parameter int TICKW    = 25,        // ~1.24 s tick at 27 MHz; shrink for sim
    parameter int CLK_HZ   = 27_000_000,
    parameter int BAUD     = 115200
)(
    input  logic       clk_in,    // 27 MHz
    input  logic       btn_s1,    // pin 3: reset, active-low, RC-debounced
    input  logic       btn_s2,    // pin 4: hold to pause, active-low
    output logic [4:0] leds,
    output logic       uart_tx
);
    localparam int WIDTH = 32, DEPTH = 4;

    // Power-on reset so the demo always self-starts; S1 also resets on demand.
    logic [11:0] por = '0;
    always_ff @(posedge clk_in) if (!(&por)) por <= por + 1'b1;
    wire rst_n = (&por) & btn_s1;    // async reset for the CAM + FSM below

    wire pause = ~btn_s2;            // S2 pressed -> hold on the current key

    // --- CAM ---
    logic            we, winvalidate;
    logic [1:0]      waddr;
    logic [WIDTH-1:0] wdata, search;
    logic            match;
    logic [1:0]      match_index;
    logic [3:0]      match_onehot;

    cam #(.DEPTH(DEPTH), .WIDTH(WIDTH)) u_cam (
        .clk(clk_in), .rst_n(rst_n),
        .we, .waddr, .wdata, .winvalidate,
        .search, .match, .match_index, .match_onehot
    );

    // --- preloaded entries ---
    function automatic [WIDTH-1:0] entry(input [1:0] i);
        case (i)
            2'd0: entry = 32'hDEAD_BEEF;
            2'd1: entry = 32'h1234_5678;
            2'd2: entry = 32'hCAFE_BABE;
            default: entry = 32'h0000_0001;
        endcase
    endfunction

    // --- scripted search keys (hits and misses) ---
    localparam int NKEYS = 8;
    function automatic [WIDTH-1:0] key(input [2:0] i);
        case (i)
            3'd0: key = 32'hDEAD_BEEF;   // hit  -> idx 0
            3'd1: key = 32'hFFFF_FFFF;   // miss
            3'd2: key = 32'h1234_5678;   // hit  -> idx 1
            3'd3: key = 32'h0000_0000;   // miss
            3'd4: key = 32'hCAFE_BABE;   // hit  -> idx 2
            3'd5: key = 32'h0000_0001;   // hit  -> idx 3
            3'd6: key = 32'hAAAA_AAAA;   // miss
            default: key = 32'hDEAD_BEEF; // hit -> idx 0
        endcase
    endfunction

    // --- ~1 Hz tick ---
    logic [TICKW-1:0] tickcnt;
    logic tick;
    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin tickcnt <= '0; tick <= 1'b0; end
        else begin
            tickcnt <= tickcnt + 1'b1;
            tick    <= (tickcnt == '1);
        end
    end

    // --- control FSM: INIT (write 4 entries) then RUN (cycle keys) ---
    typedef enum logic {INIT, RUN} state_t;
    state_t     state;
    logic [1:0] init_i;
    logic [2:0] key_i;

    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            state <= INIT; init_i <= 2'd0; key_i <= 3'd0;
            we <= 1'b0; winvalidate <= 1'b0; waddr <= 2'd0; wdata <= '0;
        end else begin
            we <= 1'b0;
            case (state)
                INIT: begin
                    we <= 1'b1; waddr <= init_i; wdata <= entry(init_i);
                    init_i <= init_i + 1'b1;
                    if (init_i == 2'd3) state <= RUN;
                end
                RUN: if (tick && !pause)
                        key_i <= (key_i == NKEYS-1) ? 3'd0 : key_i + 1'b1;
            endcase
        end
    end

    assign search = key(key_i);

    // --- report each result over UART: "key=DEADBEEF match=1 idx=0\r\n" ---
    localparam int MSGLEN = 28;

    function automatic [7:0] msg_char(input [4:0] i, input [31:0] k,
                                      input m, input [1:0] idx);
        logic [3:0] nib;
        case (i)
            0: msg_char = "k"; 1: msg_char = "e"; 2: msg_char = "y";
            3: msg_char = "=";
            4,5,6,7,8,9,10,11: begin
                nib = k >> (4*(11 - i));
                msg_char = (nib < 10) ? ("0" + nib) : ("A" + (nib - 10));
            end
            12: msg_char = " "; 13: msg_char = "m"; 14: msg_char = "a";
            15: msg_char = "t"; 16: msg_char = "c"; 17: msg_char = "h";
            18: msg_char = "=";
            19: msg_char = m ? "1" : "0";
            20: msg_char = " "; 21: msg_char = "i"; 22: msg_char = "d";
            23: msg_char = "x"; 24: msg_char = "=";
            25: msg_char = "0" + idx;
            26: msg_char = 8'h0D;
            default: msg_char = 8'h0A;
        endcase
    endfunction

    logic        tx_ready;
    logic [4:0]  msg_i;
    logic        sending;
    logic [31:0] msg_key;      // latched so the line is consistent while sending
    logic        msg_match;
    logic [1:0]  msg_idx;

    wire tx_valid = sending & tx_ready;

    // key_i advances on the tick edge, so wait one cycle for search/match to
    // settle on the new key before capturing the line
    logic start_msg;
    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) start_msg <= 1'b0;
        else        start_msg <= (state == RUN) && tick && !pause;
    end

    always_ff @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            sending <= 1'b0; msg_i <= '0;
            msg_key <= '0; msg_match <= 1'b0; msg_idx <= '0;
        end else if (!sending) begin
            if (start_msg) begin
                msg_key   <= search;
                msg_match <= match;
                msg_idx   <= match_index;
                msg_i     <= '0;
                sending   <= 1'b1;
            end
        end else if (tx_valid) begin
            if (msg_i == MSGLEN-1) sending <= 1'b0;
            else                   msg_i   <= msg_i + 1'b1;
        end
    end

    uart_tx #(.clk_freq_hz(CLK_HZ), .baud_rate(BAUD)) u_tx (
        .i_clk(clk_in), .i_rst(~rst_n),
        .i_data(msg_char(msg_i, msg_key, msg_match, msg_idx)),
        .i_valid(tx_valid), .o_ready(tx_ready), .o_uart_tx(uart_tx)
    );

    // --- LED encode (active-low at the pins) ---
    wire heartbeat = tickcnt[TICKW-1];    // pulled out of always_comb: a bit
                                          // select there makes the process
                                          // sensitive to all of tickcnt
    logic [4:0] led_int;
    always_comb begin
        led_int = 5'b00000;
        if (state == RUN) begin
            led_int[4]   = match;
            led_int[3]   = ~match;
            led_int[2]   = heartbeat;
            led_int[1:0] = match ? match_index : 2'd0;
        end
    end
    assign leds = ~led_int;
endmodule
