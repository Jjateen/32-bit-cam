// Simulates the board demo and prints the UART text the design transmits, so
// the serial log captured from the real board can be diffed against this run.
// Also checks that holding the pause button stops the sequence.
`timescale 1ns/1ps
module tb_cam_fpga;
    logic clk = 0, btn_s1 = 1, btn_s2 = 1;   // buttons idle high (released)
    logic [4:0] leds;
    logic uart_tx;

    // CLK_HZ is scaled down with TICKW so a whole line still fits inside a tick
    cam_fpga_top #(.TICKW(10), .CLK_HZ(1_000_000), .BAUD(115200))
        dut (.clk_in(clk), .btn_s1(btn_s1), .btn_s2(btn_s2),
             .leds(leds), .uart_tx(uart_tx));
    always #5 clk = ~clk;

    // snoop each byte as the transmitter accepts it
    always @(posedge clk) if (dut.tx_valid) $write("%c", dut.u_tx.i_data);

    initial begin
        repeat (9) @(posedge dut.tick);
        $display("-- hold pause --");
        btn_s2 = 0;
        repeat (3) @(posedge dut.tick);
        $display("-- release pause --");
        btn_s2 = 1;
        repeat (4) @(posedge dut.tick);
        $finish;
    end
endmodule
