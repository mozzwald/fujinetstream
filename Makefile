# Makefile for FujiNetStream Atari

# Set the location of your cc65 installation
export CC65_HOME = /usr/local/share/cc65

# cc65 Target System
CC65_TARGET   = atari

BUILD_DIR     = build
ATR_CHAT_DIR  = $(BUILD_DIR)/atr_chat_root
ATR_SEQ_DIR   = $(BUILD_DIR)/atr_udpseq_root
DIR2ATR       = dir2atr

# cc65 toolchain
CC65 ?= cl65
CFLAGS ?= -t $(CC65_TARGET)
CFLAGS_EXTRA_CHAT ?= --mapfile atari_netstream_chat.map --listing atari_netstream_chat.lst
CFLAGS_EXTRA_UDPSEQ ?= --mapfile atari_udp_sequence.map --listing atari_udp_sequence.lst

# FujiNet Library
FUJINET_LIB_VERSION = 4.9.0
FUJINET_LIB_DIR = fujinet-lib-$(CC65_TARGET)-$(FUJINET_LIB_VERSION)
FUJINET_LIB = $(FUJINET_LIB_DIR)/fujinet-$(CC65_TARGET)-$(FUJINET_LIB_VERSION).lib
FUJINET_INCLUDES = -I$(FUJINET_LIB_DIR)

NSENGINE      = $(BUILD_DIR)/NSENGINE.OBX

all: $(ATR_CHAT_DIR)/autorun.sys $(ATR_CHAT_DIR)/DOS.SYS $(ATR_CHAT_DIR)/DUP.SYS \
	$(ATR_SEQ_DIR)/autorun.sys $(ATR_SEQ_DIR)/DOS.SYS $(ATR_SEQ_DIR)/DUP.SYS \
	$(BUILD_DIR)/linux_netstream_chat \
	$(BUILD_DIR)/atari_netstream_chat.atr 

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ATR_CHAT_DIR)/autorun.sys: examples/chat/atari_netstream_chat.c handler/netstream.s examples/common/atari_netstream.cfg | $(ATR_CHAT_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CHAT) -C examples/common/atari_netstream.cfg --asm-include-dir handler/include -D HIBUILD=0 -o $@ examples/chat/atari_netstream_chat.c handler/netstream.s

$(ATR_SEQ_DIR)/autorun.sys: examples/udp-sequence/atari_udp_sequence.c handler/netstream.s examples/common/atari_netstream.cfg | $(ATR_SEQ_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_UDPSEQ) -C examples/common/atari_netstream.cfg --asm-include-dir handler/include -o $@ examples/udp-sequence/atari_udp_sequence.c handler/netstream.s

$(ATR_CHAT_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(ATR_CHAT_DIR)
	cp examples/dos/DOS.SYS $(ATR_CHAT_DIR)/DOS.SYS

$(ATR_CHAT_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(ATR_CHAT_DIR)
	cp examples/dos/DUP.SYS $(ATR_CHAT_DIR)/DUP.SYS

$(ATR_SEQ_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(ATR_SEQ_DIR)
	cp examples/dos/DOS.SYS $(ATR_SEQ_DIR)/DOS.SYS

$(ATR_SEQ_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(ATR_SEQ_DIR)
	cp examples/dos/DUP.SYS $(ATR_SEQ_DIR)/DUP.SYS

$(BUILD_DIR)/linux_netstream_chat: examples/chat/linux_netstream_chat.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/chat/linux_netstream_chat.c

$(BUILD_DIR)/linux_udp_sequence_server: examples/udp-sequence/linux_udp_sequence_server.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/udp-sequence/linux_udp_sequence_server.c

$(ATR_CHAT_DIR): | $(BUILD_DIR)
	mkdir -p $(ATR_CHAT_DIR)

$(ATR_SEQ_DIR): | $(BUILD_DIR)
	mkdir -p $(ATR_SEQ_DIR)

$(BUILD_DIR)/atari_netstream_chat.atr: $(ATR_CHAT_DIR)/autorun.sys $(ATR_CHAT_DIR)/DOS.SYS $(ATR_CHAT_DIR)/DUP.SYS | $(BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(ATR_CHAT_DIR)

$(BUILD_DIR)/atari_udp_sequence.atr: $(ATR_SEQ_DIR)/autorun.sys $(ATR_SEQ_DIR)/DOS.SYS $(ATR_SEQ_DIR)/DUP.SYS | $(BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(ATR_SEQ_DIR)

clean:
	rm -rf $(BUILD_DIR)/*

.PHONY: all clean
