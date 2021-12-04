# Makefile for ArcDVI
#
# This builds firmware (for embedded picorv32 CPU), and a bitstream for ECP5.
# Work needed to refactor & support other FPGA flows.
#
# This is a mish-mash in origin: the top is copyright 2021 Matt Evans,
# the middle (firmware build) is derived from the picorv32/picosoc project,
# and the end (bitstream build) is derived from the ulx3s-misc examples project.
#


CROSS_COMPILE ?= riscv32-unknown-elf-
HIRES_MODE ?= 0

VERILOG_LOCAL_FILES = src/soc_top.v
VERILOG_LOCAL_FILES += src/vidc_capture.v
VERILOG_LOCAL_FILES += src/video.v
VERILOG_LOCAL_FILES += src/video_timing.v
VERILOG_LOCAL_FILES += src/clocks.v

VERILOG_EXTERNAL_FILES = external-src/picosocme.v
VERILOG_EXTERNAL_FILES += external-src/picorv32.v
VERILOG_EXTERNAL_FILES += external-src/simpleuart.v

VERILOG_EXTERNAL_FILES_NOSIM = external-src/ecp5pll.sv
VERILOG_EXTERNAL_FILES_NOSIM += external-src/vga2dvid.v
VERILOG_EXTERNAL_FILES_NOSIM += external-src/tmds_encoder.v

PRJ_VERILOG_FILES = $(VERILOG_LOCAL_FILES) $(VERILOG_EXTERNAL_FILES)
BUILD_VERILOG_FILES = $(PRJ_VERILOG_FILES) $(VERILOG_EXTERNAL_FILES_NOSIM)

COMPRESSED_ISA = C
MEM_SIZE = 16384

FIRMWARE_OBJS = firmware/start.o firmware/print.o firmware/uart.o firmware/commands.o firmware/libcfns.o firmware/main.o firmware/irq.o firmware/vidc_regs.o firmware/video.o

CLEAN_FILES = *~ src/*~ firmware/*~ tb/*~
CLEAN_FILES += firmware/*.o firmware/firmware.elf firmware/firmware.hex firmware/firmware.map firmware/firmware.bin
CLEAN_FILES += *.vvp *.vcd
CLEAN_FILES += *.bit *.config *.svf *.json

all:	tb_top.wave

clean:
	rm -f $(CLEAN_FILES)

################################################################################
# Test/sim stuff:
VDEFS = $(subst C,-DCOMPRESSED_ISA,$(COMPRESSED_ISA))
VDEFS += -DMEM_SIZE=$(MEM_SIZE)
YOSYS_VDEFS = $(subst -D,,$(VDEFS))

# Build options
ifneq ($(HIRES_MODE), 0)
	VDEFS += -DHIRES_MODE=1
endif

IVERILOG = iverilog
IVPATHS = -y src -y external-src
IVOPTS = -g2005-sv
IVOPTS += $(VDEFS)


.PHONY: wave
wave:	tb_top.wave

.PHONY:	sim
sim:	tb_top.vcd

%.vcd:	%.vvp
	vvp $<

.PHONY: %.wave
%.wave:	%.vcd
	gtkwave $<

tb_top.vvp:	tb/tb_top.v firmware/firmware.hex
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $<

tb_comp_video_timing.vvp:	tb/tb_comp_video_timing.v
	$(IVERILOG) $(IVOPTS) $(IVPATHS) -o $@ $^


################################################################################
# Firmware build, from picosoc makefile:
TOOLCHAIN_PREFIX = $(CROSS_COMPILE)

firmware/firmware.hex: firmware/firmware.bin firmware/makehex.py
	$(PYTHON) firmware/makehex.py $< $$(( $(MEM_SIZE) / 4 )) > $@

firmware/firmware.bin: firmware/firmware.elf
	$(TOOLCHAIN_PREFIX)objcopy -O binary $< $@
	chmod -x $@

firmware/firmware.elf: $(FIRMWARE_OBJS) $(TEST_OBJS) firmware/sections.lds
	$(TOOLCHAIN_PREFIX)gcc -Os -ffreestanding -nostdlib -o $@ \
		-Wl,-Bstatic,-T,firmware/sections.lds,-Map,firmware/firmware.map,--strip-debug \
		$(FIRMWARE_OBJS) $(TEST_OBJS) -lgcc
	chmod -x $@

firmware/start.o: firmware/start.S
	$(TOOLCHAIN_PREFIX)gcc -c -march=rv32im$(subst C,c,$(COMPRESSED_ISA)) -o $@ $<

firmware/%.o: firmware/%.c
	$(TOOLCHAIN_PREFIX)gcc -c -march=rv32i$(subst C,c,$(COMPRESSED_ISA)) -Os --std=c99 $(GCC_WARNS) -ffreestanding -nostdlib -o $@ $<


################################################################################
# Build for ECP5 using Yosys & prjtrellis:
# These rules are based on those from the ulx3s example makefiles
#

# Tools
TRELLIS_SH ?= /usr/local/share/trellis
TRELLIS_LIB ?= /usr/local/lib/trellis
VHDL2VL ?= vhd2vl
YOSYS ?= yosys
NEXTPNR-ECP5 ?= nextpnr-ecp5
ECPPLL ?= LANG=C ecppll
ECPPACK ?= LANG=C ecppack
#BIT2SVF ?= $(TRELLIS)/tools/bit_to_svf.py
TRELLISDB ?= $(TRELLIS_SH)/database
LIBTRELLIS ?= $(TRELLIS_LIB)/libtrellis

# Config
NEXTPNR_OPTIONS = --timing-allow-fail #--lpf-allow-unconstrained
NEXTPNR_OPTIONS += --report timing.json --placer heap --router router1 --starttemp 20
PROJECT = dvi
BOARD = ulx3s
TOP_MODULE = soc_top

include platform/$(BOARD)/make.plat

# Rules:
bitstream: $(BOARD)_$(FPGA_SIZE)f_$(PROJECT).bit $(BOARD)_$(FPGA_SIZE)f_$(PROJECT).svf

# # VHDL to VERILOG conversion (Not used here)
# # convert all *.vhd filenames to .v extension
# VHDL_TO_VERILOG_FILES = $(VHDL_FILES:.vhd=.v)
# # implicit conversion rule
# %.v: %.vhd
# 	$(VHDL2VL) $< $@

$(PROJECT).json: $(BUILD_VERILOG_FILES) $(VHDL_TO_VERILOG_FILES) firmware/firmware.hex
	$(YOSYS) \
	-p "read -define $(YOSYS_VDEFS)" \
	-p "read -sv $(BUILD_VERILOG_FILES) $(VHDL_TO_VERILOG_FILES)" \
	-p "hierarchy -top ${TOP_MODULE}" \
	-p "synth_ecp5 ${YOSYS_OPTIONS} -json ${PROJECT}.json"

$(BOARD)_$(FPGA_SIZE)f_$(PROJECT).config: $(PROJECT).json $(BASECFG)
	$(NEXTPNR-ECP5) $(NEXTPNR_OPTIONS) --$(FPGA_K)k --package $(FPGA_PACKAGE) --json $(PROJECT).json --lpf $(CONSTRAINTS) --textcfg $@

$(BOARD)_$(FPGA_SIZE)f_$(PROJECT).bit: $(BOARD)_$(FPGA_SIZE)f_$(PROJECT).config
	$(ECPPACK) $(IDCODE_CHIPID) --compress --freq $(FLASH_READ_MHZ) --input $< --bit $@
#	$(ECPPACK) $(IDCODE_CHIPID) --compress --freq $(FLASH_READ_MHZ) --spimode $(FLASH_READ_MODE) --input $< --bit $@

$(BOARD)_$(FPGA_SIZE)f_$(PROJECT).svf: $(BOARD)_$(FPGA_SIZE)f_$(PROJECT).config
	$(ECPPACK) $(IDCODE_CHIPID) $< --compress --freq $(FLASH_READ_MHZ) --svf-rowsize 800000 --svf $@
#	$(ECPPACK) $(IDCODE_CHIPID) $< --compress --freq $(FLASH_READ_MHZ) --spimode $(FLASH_READ_MODE) --svf-rowsize 800000 --svf $@

# program SRAM with OPENFPGALOADER
prog: program_ofl
program_ofl: $(BOARD)_$(FPGA_SIZE)f_$(PROJECT).bit
	$(OPENFPGALOADER) $(OPENFPGALOADER_OPTIONS) $<

# Noddy help:
help:
	@echo "Make targets include:"
	@echo "	bitstream	Build FPGA bitstream"
	@echo "	prog		Program bitstream"
