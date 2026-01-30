# Makefile for FujiNetStream Atari

# Mad Assembler
MADS=/usr/local/bin/mads

# Set the location of your cc65 installation
export CC65_HOME = /usr/share/cc65

# cc65 Target System
CC65_TARGET   = atari

BUILD_DIR     = build

# Base address for handler-esque binary to exist on Atari
HANDLER_BASE  = 10240

# cc65 toolchain
CC65 ?= cl65
CFLAGS ?= -t $(CC65_TARGET)

# FujiNet Library
FUJINET_LIB_VERSION = 4.9.0
FUJINET_LIB_DIR = fujinet-lib-$(CC65_TARGET)-$(FUJINET_LIB_VERSION)
FUJINET_LIB = $(FUJINET_LIB_DIR)/fujinet-$(CC65_TARGET)-$(FUJINET_LIB_VERSION).lib
FUJINET_INCLUDES = -I$(FUJINET_LIB_DIR)

all: $(BUILD_DIR)/netstream.obx $(BUILD_DIR)/netstream_engine.obx $(BUILD_DIR)/NSENGINE.OBX $(BUILD_DIR)/netstream_smoke.xex

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Build stripped concurrent-mode engine
build/netstream.obx: handler/handler.s | $(BUILD_DIR)
	$(MADS) handler/handler.s -i:handler/include -d:BASEADDR=$(HANDLER_BASE) -d:HIBUILD=0 -s -p -o:$@

build/netstream_engine.obx: handler/netstream.s | $(BUILD_DIR)
	$(MADS) handler/netstream.s -i:handler/include -d:BASEADDR=$(HANDLER_BASE) -d:HIBUILD=0 -s -p -o:$@

$(BUILD_DIR)/NSENGINE.OBX: $(BUILD_DIR)/netstream_engine.obx | $(BUILD_DIR)
	cp $< $@

$(BUILD_DIR)/netstream_smoke.xex: tests/netstream_smoke.c tests/netstream_api.s tests/atari_netstream.cfg | $(BUILD_DIR)
	$(CC65) $(CFLAGS) -C tests/atari_netstream.cfg -o $@ tests/netstream_smoke.c tests/netstream_api.s

clean:
	rm -f $(BUILD_DIR)/*

.PHONY: all clean
