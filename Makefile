# CAM: simulation, timing diagram, FPGA build, and the LLVM pass.
# Run `make` for the target list.

HW      := hardware
WAVES   := $(HW)/waves
FPGA    := $(HW)/fpga
SW      := software

IVFLAGS := -g2012
DEVICE  := GW1NR-LV9QN88PC6/I5
FAMILY  := GW1N-9C
PORT    ?= /dev/ttyUSB1
BAUD    := 115200

# VCD timescale is 1 ps; the demo clock is 10 ns
CYCLE_PS      := 10000
FIRST_EDGE_PS := 5000
WINDOW_PS     := 130000
NLINES        := 8              # one full pass of the key list

.PHONY: help sim waves bitstream flash verify-hw pass count verify-pass verify clean

help:
	@echo "sim          run the CAM testbench"
	@echo "waves        generate the timing diagram from the simulation VCD"
	@echo "bitstream    synthesise and pack for the Tang Nano 9K"
	@echo "flash        load the bitstream onto the board"
	@echo "verify-hw    diff the board's UART output against simulation"
	@echo "pass         build the LLVM plugin"
	@echo "count        run the pass over software/test.c"
	@echo "verify-pass  check the pass's counts against the IR"
	@echo "verify       sim + verify-pass (everything not needing the board)"
	@echo "clean        remove build products"

# ---------------------------------------------------------------- simulation

$(HW)/cam.vvp: $(HW)/cam.sv $(HW)/tb_cam.sv
	iverilog $(IVFLAGS) -o $@ $^

sim: $(HW)/cam.vvp
	@vvp $<

# ---------------------------------------------------------------- timing diagram
# iverilog/vvp -> VCD -> vcd2wavedrom -> JSON -> wavedrom-cli -> png/svg
# Nothing here is hand-drawn; only wavedrom.cfg.json picks the signals shown.

$(WAVES)/wave.vvp: $(HW)/cam.sv $(WAVES)/tb_cam_wave.sv
	iverilog $(IVFLAGS) -o $@ $^

$(WAVES)/cam_wave.vcd: $(WAVES)/wave.vvp
	@cd $(WAVES) && echo "cyc,rst_n,we,waddr,wdata,search,match,idx,onehot,note" \
	  && vvp wave.vvp | grep -v VCD

$(WAVES)/cam_timing.png: $(WAVES)/cam_wave.vcd $(WAVES)/wavedrom.cfg.json
	cd $(WAVES) && python3 -m vcd2wavedrom.vcd2wavedrom -i cam_wave.vcd \
	    -c wavedrom.cfg.json -r $(CYCLE_PS) -f $(FIRST_EDGE_PS) -t $(WINDOW_PS) \
	    -o cam_timing.json
	@cd $(WAVES) && python3 -c "import json; \
	d=json.load(open('cam_timing.json')); \
	d['head']={'text':'4-entry 32-bit CAM: fill, hit, miss, invalidate','tick':0}; \
	d['foot']={'text':'generated from cam_wave.vcd; writes are registered, so an entry written in one cycle first matches in the next'}; \
	json.dump(d,open('cam_timing.json','w'),indent=2)"
	cd $(WAVES) && npx --yes wavedrom-cli -i cam_timing.json \
	    -s cam_timing.svg -p cam_timing.png

waves: $(WAVES)/cam_timing.png

# ---------------------------------------------------------------- FPGA

FPGA_SRC := $(FPGA)/cam_fpga_top.sv $(HW)/cam.sv $(FPGA)/uart_tx.v

$(FPGA)/cam.json: $(FPGA_SRC)
	yosys -q -p "read_verilog -sv $(FPGA_SRC); \
	    synth_gowin -top cam_fpga_top -json $@"

$(FPGA)/cam_pnr.json: $(FPGA)/cam.json $(FPGA)/cam_demo.cst
	nextpnr-himbaechel --json $< --write $@ --device "$(DEVICE)" \
	    --vopt family=$(FAMILY) --vopt cst=$(FPGA)/cam_demo.cst

$(FPGA)/cam.fs: $(FPGA)/cam_pnr.json
	gowin_pack -d $(FAMILY) -o $@ $<

bitstream: $(FPGA)/cam.fs

# SRAM programming: lost on unplug. `make flash PERSIST=1` writes flash instead.
flash: $(FPGA)/cam.fs
	openFPGALoader -b tangnano9k $(if $(PERSIST),-f) $<

$(FPGA)/cf.vvp: $(FPGA_SRC) $(FPGA)/tb_cam_fpga.sv
	iverilog $(IVFLAGS) -o $@ $^

# Compare what the board transmits with what the simulation transmits, so
# "works on hardware" means matching bytes rather than watching LEDs.
verify-hw: $(FPGA)/cf.vvp
	@vvp $< | grep -oE 'key=[0-9A-F]+ match=[01] idx=[0-9]' \
	    | head -$(NLINES) > /tmp/cam_sim.txt
	@echo "simulation:"; cat /tmp/cam_sim.txt
	@stty -F $(PORT) $(BAUD) raw -echo
	@echo "board on $(PORT):"
	@timeout 14 cat $(PORT) | tr -d '\r' \
	    | grep -oE 'key=[0-9A-F]+ match=[01] idx=[0-9]' > /tmp/cam_raw.txt || true
	@first=$$(head -1 /tmp/cam_sim.txt); \
	start=$$(grep -n -m1 -F "$$first" /tmp/cam_raw.txt | cut -d: -f1); \
	if [ -z "$$start" ]; then echo "FAIL: board output never synced"; exit 1; fi; \
	tail -n +$$start /tmp/cam_raw.txt | head -$(NLINES) > /tmp/cam_hw.txt; \
	cat /tmp/cam_hw.txt; \
	if diff -u /tmp/cam_sim.txt /tmp/cam_hw.txt; then \
	    echo "PASS: board output matches simulation ($(NLINES) lines)"; \
	else echo "FAIL: board and simulation differ"; exit 1; fi

# ---------------------------------------------------------------- LLVM pass

PLUGIN := $(SW)/build/libCountMemOps.so

$(PLUGIN): $(SW)/CountMemOps.cpp $(SW)/CMakeLists.txt
	cmake -S $(SW) -B $(SW)/build -DCMAKE_BUILD_TYPE=Release >/dev/null
	cmake --build $(SW)/build >/dev/null
	@echo "built $@"

pass: $(PLUGIN)

# -disable-O0-optnone: without it clang marks every function optnone at -O0,
# which blocks analysis. The IR is unoptimised either way.
$(SW)/test.ll: $(SW)/test.c
	clang -O0 -Xclang -disable-O0-optnone -S -emit-llvm $< -o $@

count: $(PLUGIN) $(SW)/test.ll
	@opt -load-pass-plugin=$(PLUGIN) -passes=count-mem-ops -disable-output $(SW)/test.ll

# Count the same instructions in the IR text independently and compare, rather
# than trusting the pass's own output.
verify-pass: $(PLUGIN) $(SW)/test.ll
	@out=$$(opt -load-pass-plugin=$(PLUGIN) -passes=count-mem-ops \
	          -disable-output $(SW)/test.ll 2>&1); \
	echo "$$out"; \
	pl=$$(echo "$$out" | awk '/TOTAL/{print $$1}'); \
	ps=$$(echo "$$out" | awk '/TOTAL/{print $$2}'); \
	il=$$(grep -cE '^[[:space:]]+(%[^ ]+ = )?load ' $(SW)/test.ll); \
	is=$$(grep -cE '^[[:space:]]+store ' $(SW)/test.ll); \
	echo; echo "pass:  loads=$$pl stores=$$ps"; \
	echo "IR:    loads=$$il stores=$$is   (counted from test.ll independently)"; \
	if [ "$$pl" = "$$il" ] && [ "$$ps" = "$$is" ]; then \
	    echo "PASS: counts agree with the IR"; \
	else echo "FAIL: counts disagree"; exit 1; fi

verify: sim verify-pass

clean:
	rm -f $(HW)/*.vvp $(WAVES)/*.vvp $(WAVES)/cam_wave.vcd $(FPGA)/*.vvp \
	      $(FPGA)/cam.json $(FPGA)/cam_pnr.json $(FPGA)/cam.fs $(SW)/test.ll
	rm -rf $(SW)/build
