# Third-party code

Everything in this repository is my own work except the file below.

## `hardware/fpga/uart_tx.v`

A UART transmitter, reused so the CAM demo can report results over serial. It is
derived from `corescore_emitter_uart` by Olof Kindgren, from the
[corescore](https://github.com/olofk/corescore) project
([original file](https://github.com/olofk/corescore/blob/master/rtl/corescore_emitter_uart.v)),
licensed under Apache-2.0: https://www.apache.org/licenses/LICENSE-2.0

I had already vendored it into my RISC-V SoC project and copied it here so this
repository builds standalone. My only change was removing a simulation-only
`$dumpfile`/`$dumpvars` block, which would otherwise overwrite the VCD written by
the testbenches.
