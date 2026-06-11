# Makefile for FujiNetStream Atari

# Mad Assembler
MADS ?= mads

# Set the location of your cc65 installation
CC65_HOME ?= /usr/share/cc65
export CC65_HOME

# cc65 Target System
CC65_TARGET   = atari

BUILD_DIR     = build
MADS_BUILD_DIR = $(BUILD_DIR)/mads
CA65_BUILD_DIR = $(BUILD_DIR)/ca65
MADS_ATR_CHAT_DIR = $(MADS_BUILD_DIR)/atr_chat_root
MADS_ATR_SEQ_DIR  = $(MADS_BUILD_DIR)/atr_udpseq_root
CA65_ATR_CHAT_DIR = $(CA65_BUILD_DIR)/atr_chat_root
CA65_ATR_SEQ_DIR  = $(CA65_BUILD_DIR)/atr_udpseq_root
DIR2ATR       = dir2atr

# Base address for MADS handler-esque binary to exist on Atari.
HANDLER_BASE  = 10240

# cc65 toolchain
CC65 ?= cl65
CFLAGS ?= -t $(CC65_TARGET)
CFLAGS_EXTRA_MADS_CHAT ?=
CFLAGS_EXTRA_MADS_UDPSEQ ?=
CFLAGS_EXTRA_CA65_CHAT ?= --mapfile $(CA65_BUILD_DIR)/atari_netstream_chat.map --listing $(CA65_BUILD_DIR)/atari_netstream_chat.lst
CFLAGS_EXTRA_CA65_UDPSEQ ?= --mapfile $(CA65_BUILD_DIR)/atari_udp_sequence.map --listing $(CA65_BUILD_DIR)/atari_udp_sequence.lst

# FujiNet Library
FUJINET_LIB_VERSION = 4.9.0
FUJINET_LIB_DIR = fujinet-lib-$(CC65_TARGET)-$(FUJINET_LIB_VERSION)
FUJINET_LIB = $(FUJINET_LIB_DIR)/fujinet-$(CC65_TARGET)-$(FUJINET_LIB_VERSION).lib
FUJINET_INCLUDES = -I$(FUJINET_LIB_DIR)

MADS_NSENGINE = $(MADS_BUILD_DIR)/NSENGINE.OBX

all: mads ca65 linux

mads: mads-chat mads-udpseq
ca65: ca65-chat ca65-udpseq
linux: $(BUILD_DIR)/linux_netstream_chat $(BUILD_DIR)/linux_udp_sequence_server

mads-chat: $(MADS_BUILD_DIR)/atari_netstream_chat.atr
mads-udpseq: $(MADS_BUILD_DIR)/atari_udp_sequence.atr
ca65-chat: $(CA65_BUILD_DIR)/atari_netstream_chat.atr
ca65-udpseq: $(CA65_BUILD_DIR)/atari_udp_sequence.atr

$(BUILD_DIR) $(MADS_BUILD_DIR) $(CA65_BUILD_DIR):
	mkdir -p $@

$(MADS_NSENGINE): handler/mads/netstream.s | $(MADS_BUILD_DIR)
	$(MADS) handler/mads/netstream.s -i:handler/mads/include -d:BASEADDR=$(HANDLER_BASE) -d:HIBUILD=0 -s -p -o:$@

$(MADS_ATR_CHAT_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_CHAT_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_SEQ_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_SEQ_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_CHAT_DIR)/autorun.sys: examples/chat/atari_netstream_chat.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_CHAT_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_CHAT) -C examples/common/atari_netstream.cfg -o $@ examples/chat/atari_netstream_chat.c examples/common/netstream_api.s

$(MADS_ATR_SEQ_DIR)/autorun.sys: examples/udp-sequence/atari_udp_sequence.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_SEQ_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_UDPSEQ) -C examples/common/atari_netstream.cfg -o $@ examples/udp-sequence/atari_udp_sequence.c examples/common/netstream_api.s

$(CA65_ATR_CHAT_DIR)/autorun.sys: examples/chat/atari_netstream_chat.c handler/ca65/netstream.s examples/common/atari_netstream.cfg | $(CA65_ATR_CHAT_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_CHAT) -C examples/common/atari_netstream.cfg --asm-include-dir handler/ca65/include -D NETSTREAM_LINKED_HANDLER -D HIBUILD=0 -o $@ examples/chat/atari_netstream_chat.c handler/ca65/netstream.s

$(CA65_ATR_SEQ_DIR)/autorun.sys: examples/udp-sequence/atari_udp_sequence.c handler/ca65/netstream.s examples/common/atari_netstream.cfg | $(CA65_ATR_SEQ_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_UDPSEQ) -C examples/common/atari_netstream.cfg --asm-include-dir handler/ca65/include -D NETSTREAM_LINKED_HANDLER -D HIBUILD=0 -o $@ examples/udp-sequence/atari_udp_sequence.c handler/ca65/netstream.s

$(MADS_ATR_CHAT_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(MADS_ATR_CHAT_DIR)
	cp examples/dos/DOS.SYS $@

$(CA65_ATR_CHAT_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(CA65_ATR_CHAT_DIR)
	cp examples/dos/DOS.SYS $@

$(MADS_ATR_CHAT_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(MADS_ATR_CHAT_DIR)
	cp examples/dos/DUP.SYS $@

$(CA65_ATR_CHAT_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(CA65_ATR_CHAT_DIR)
	cp examples/dos/DUP.SYS $@

$(MADS_ATR_SEQ_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(MADS_ATR_SEQ_DIR)
	cp examples/dos/DOS.SYS $@

$(CA65_ATR_SEQ_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(CA65_ATR_SEQ_DIR)
	cp examples/dos/DOS.SYS $@

$(MADS_ATR_SEQ_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(MADS_ATR_SEQ_DIR)
	cp examples/dos/DUP.SYS $@

$(CA65_ATR_SEQ_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(CA65_ATR_SEQ_DIR)
	cp examples/dos/DUP.SYS $@

$(BUILD_DIR)/linux_netstream_chat: examples/chat/linux_netstream_chat.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/chat/linux_netstream_chat.c

$(BUILD_DIR)/linux_udp_sequence_server: examples/udp-sequence/linux_udp_sequence_server.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/udp-sequence/linux_udp_sequence_server.c

$(MADS_ATR_CHAT_DIR) $(MADS_ATR_SEQ_DIR): | $(MADS_BUILD_DIR)
	mkdir -p $@

$(CA65_ATR_CHAT_DIR) $(CA65_ATR_SEQ_DIR): | $(CA65_BUILD_DIR)
	mkdir -p $@

$(MADS_BUILD_DIR)/atari_netstream_chat.atr: $(MADS_ATR_CHAT_DIR)/autorun.sys $(MADS_ATR_CHAT_DIR)/NSENGINE.OBX $(MADS_ATR_CHAT_DIR)/DOS.SYS $(MADS_ATR_CHAT_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_CHAT_DIR)

$(MADS_BUILD_DIR)/atari_udp_sequence.atr: $(MADS_ATR_SEQ_DIR)/autorun.sys $(MADS_ATR_SEQ_DIR)/NSENGINE.OBX $(MADS_ATR_SEQ_DIR)/DOS.SYS $(MADS_ATR_SEQ_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_SEQ_DIR)

$(CA65_BUILD_DIR)/atari_netstream_chat.atr: $(CA65_ATR_CHAT_DIR)/autorun.sys $(CA65_ATR_CHAT_DIR)/DOS.SYS $(CA65_ATR_CHAT_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_CHAT_DIR)

$(CA65_BUILD_DIR)/atari_udp_sequence.atr: $(CA65_ATR_SEQ_DIR)/autorun.sys $(CA65_ATR_SEQ_DIR)/DOS.SYS $(CA65_ATR_SEQ_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_SEQ_DIR)

clean:
	rm -rf $(BUILD_DIR)/*

.PHONY: all clean mads ca65 linux mads-chat mads-udpseq ca65-chat ca65-udpseq
