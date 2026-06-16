# Makefile for FujiNetStream Atari

# Mad Assembler
MADS ?= mads
CA65 ?= ca65

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
MADS_ATR_SPEEDTEST_DIR = $(MADS_BUILD_DIR)/atr_speedtest_root
MADS_ATR_PSEUDOGAME_DIR = $(MADS_BUILD_DIR)/atr_pseudogame_root
CA65_ATR_CHAT_DIR = $(CA65_BUILD_DIR)/atr_chat_root
CA65_ATR_SEQ_DIR  = $(CA65_BUILD_DIR)/atr_udpseq_root
CA65_ATR_SPEEDTEST_DIR = $(CA65_BUILD_DIR)/atr_speedtest_root
CA65_ATR_PSEUDOGAME_DIR = $(CA65_BUILD_DIR)/atr_pseudogame_root
DIR2ATR       = dir2atr

# Base address for MADS handler-esque binary to exist on Atari.
HANDLER_BASE  = 10240

# Internal receive buffer size for both handler syntaxes. The handler sources
# default to 128 bytes when this is not supplied, but the examples use 1024 so
# bursty test traffic has room while the Atari main loop drains the buffer.
NETSTREAM_INPUT_BUFSIZE ?= 1024

# Speedtest client defaults. Rebuild with -B after changing these values.
# Matrix rows:
#   UDP paced:    SPEEDTEST_TCP=0 SPEEDTEST_UNPACED=0
#   UDP unpaced:  SPEEDTEST_TCP=0 SPEEDTEST_UNPACED=1
#   TCP paced:    SPEEDTEST_TCP=1 SPEEDTEST_UNPACED=0
#   TCP unpaced:  SPEEDTEST_TCP=1 SPEEDTEST_UNPACED=1
SPEEDTEST_TCP ?= 0
SPEEDTEST_UNPACED ?= 0
SPEEDTEST_HOST ?= 127.0.0.2
SPEEDTEST_PORT ?= 9000
SPEEDTEST_DEFINES = -D NETSTREAM_AUTOSTART=1 -D NETSTREAM_DEFAULT_HOST=\"$(SPEEDTEST_HOST)\" -D NETSTREAM_DEFAULT_TCP=$(SPEEDTEST_TCP) -D NETSTREAM_DEFAULT_UNPACED=$(SPEEDTEST_UNPACED) -D NETSTREAM_DEFAULT_PORT=$(SPEEDTEST_PORT)

GAME_HOST ?= 127.0.0.2
GAME_PORT ?= 9000
GAME_UNPACED ?= 0
GAME_DEFINES = -D GAME_DEFAULT_HOST=\"$(GAME_HOST)\" -D GAME_DEFAULT_PORT=$(GAME_PORT) -D GAME_UNPACED=$(GAME_UNPACED)

# cc65 toolchain
CC65 ?= cl65
CFLAGS ?= -t $(CC65_TARGET)
CFLAGS_EXTRA_MADS_CHAT ?=
CFLAGS_EXTRA_MADS_UDPSEQ ?=
CFLAGS_EXTRA_MADS_SPEEDTEST ?=
CFLAGS_EXTRA_MADS_PSEUDOGAME ?=
CFLAGS_EXTRA_CA65_CHAT ?= --mapfile $(CA65_BUILD_DIR)/atari_netstream_chat.map --listing $(CA65_BUILD_DIR)/atari_netstream_chat.lst
CFLAGS_EXTRA_CA65_UDPSEQ ?= --mapfile $(CA65_BUILD_DIR)/atari_udp_sequence.map --listing $(CA65_BUILD_DIR)/atari_udp_sequence.lst
CFLAGS_EXTRA_CA65_SPEEDTEST ?= --mapfile $(CA65_BUILD_DIR)/atari_netstream_speedtest.map --listing $(CA65_BUILD_DIR)/atari_netstream_speedtest.lst
CFLAGS_EXTRA_CA65_PSEUDOGAME ?= --mapfile $(CA65_BUILD_DIR)/atari_pseudo_game_20hz.map --listing $(CA65_BUILD_DIR)/atari_pseudo_game_20hz.lst

# FujiNet Library
FUJINET_LIB_VERSION = 4.9.0
FUJINET_LIB_DIR = fujinet-lib-$(CC65_TARGET)-$(FUJINET_LIB_VERSION)
FUJINET_LIB = $(FUJINET_LIB_DIR)/fujinet-$(CC65_TARGET)-$(FUJINET_LIB_VERSION).lib
FUJINET_INCLUDES = -I$(FUJINET_LIB_DIR)

MADS_NSENGINE = $(MADS_BUILD_DIR)/NSENGINE.OBX
CA65_HANDLER_OBJ = $(CA65_BUILD_DIR)/netstream.o

all: mads ca65 linux

mads: mads-chat mads-udpseq mads-speedtest mads-pseudogame
ca65: ca65-chat ca65-udpseq ca65-speedtest ca65-pseudogame
linux: $(BUILD_DIR)/linux_netstream_chat $(BUILD_DIR)/linux_udp_sequence_server $(BUILD_DIR)/netstream_speed_server $(BUILD_DIR)/netstream_pseudo_game_server
speedtest: mads-speedtest ca65-speedtest $(BUILD_DIR)/netstream_speed_server
pseudogame: mads-pseudogame ca65-pseudogame $(BUILD_DIR)/netstream_pseudo_game_server
handlers: mads-handler ca65-handler
mads-handler: $(MADS_NSENGINE)
ca65-handler: $(CA65_HANDLER_OBJ)

mads-chat: $(MADS_BUILD_DIR)/atari_netstream_chat.atr
mads-udpseq: $(MADS_BUILD_DIR)/atari_udp_sequence.atr
mads-speedtest: $(MADS_BUILD_DIR)/atari_netstream_speedtest.atr
mads-pseudogame: $(MADS_BUILD_DIR)/atari_pseudo_game_20hz.atr
ca65-chat: $(CA65_BUILD_DIR)/atari_netstream_chat.atr
ca65-udpseq: $(CA65_BUILD_DIR)/atari_udp_sequence.atr
ca65-speedtest: $(CA65_BUILD_DIR)/atari_netstream_speedtest.atr
ca65-pseudogame: $(CA65_BUILD_DIR)/atari_pseudo_game_20hz.atr

$(BUILD_DIR) $(MADS_BUILD_DIR) $(CA65_BUILD_DIR):
	mkdir -p $@

$(MADS_NSENGINE): handler/mads/netstream.s | $(MADS_BUILD_DIR)
	$(MADS) handler/mads/netstream.s -i:handler/mads/include -d:BASEADDR=$(HANDLER_BASE) -d:INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) -d:HIBUILD=0 -s -p -o:$@

$(CA65_HANDLER_OBJ): handler/ca65/netstream.s | $(CA65_BUILD_DIR)
	$(CA65) -t $(CC65_TARGET) --create-dep $(@:.o=.d) --include-dir handler/ca65/include -D INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) -o $@ $<

$(MADS_ATR_CHAT_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_CHAT_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_SEQ_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_SEQ_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_SPEEDTEST_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_SPEEDTEST_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_PSEUDOGAME_DIR)/NSENGINE.OBX: $(MADS_NSENGINE) | $(MADS_ATR_PSEUDOGAME_DIR)
	cp $(MADS_NSENGINE) $@

$(MADS_ATR_CHAT_DIR)/autorun.sys: examples/chat/atari_netstream_chat.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_CHAT_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_CHAT) -C examples/common/atari_netstream.cfg -o $@ examples/chat/atari_netstream_chat.c examples/common/netstream_api.s

$(MADS_ATR_SEQ_DIR)/autorun.sys: examples/udp-sequence/atari_udp_sequence.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_SEQ_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_UDPSEQ) -C examples/common/atari_netstream.cfg -o $@ examples/udp-sequence/atari_udp_sequence.c examples/common/netstream_api.s

$(MADS_ATR_SPEEDTEST_DIR)/autorun.sys: examples/speedtest/atari_netstream_speedtest.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_SPEEDTEST_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_SPEEDTEST) -C examples/common/atari_netstream.cfg -D INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) $(SPEEDTEST_DEFINES) -o $@ examples/speedtest/atari_netstream_speedtest.c examples/common/netstream_api.s

$(MADS_ATR_PSEUDOGAME_DIR)/autorun.sys: examples/pseudo_game_20hz/atari_pseudo_game_20hz.c examples/common/netstream_api.s examples/common/atari_netstream.cfg | $(MADS_ATR_PSEUDOGAME_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_MADS_PSEUDOGAME) -C examples/common/atari_netstream.cfg -D INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) $(GAME_DEFINES) -o $@ examples/pseudo_game_20hz/atari_pseudo_game_20hz.c examples/common/netstream_api.s

$(CA65_ATR_CHAT_DIR)/autorun.sys: examples/chat/atari_netstream_chat.c $(CA65_HANDLER_OBJ) examples/common/atari_netstream.cfg | $(CA65_ATR_CHAT_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_CHAT) -C examples/common/atari_netstream.cfg -D NETSTREAM_LINKED_HANDLER -o $@ examples/chat/atari_netstream_chat.c $(CA65_HANDLER_OBJ)

$(CA65_ATR_SEQ_DIR)/autorun.sys: examples/udp-sequence/atari_udp_sequence.c $(CA65_HANDLER_OBJ) examples/common/atari_netstream.cfg | $(CA65_ATR_SEQ_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_UDPSEQ) -C examples/common/atari_netstream.cfg -D NETSTREAM_LINKED_HANDLER -o $@ examples/udp-sequence/atari_udp_sequence.c $(CA65_HANDLER_OBJ)

$(CA65_ATR_SPEEDTEST_DIR)/autorun.sys: examples/speedtest/atari_netstream_speedtest.c $(CA65_HANDLER_OBJ) examples/common/atari_netstream.cfg | $(CA65_ATR_SPEEDTEST_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_SPEEDTEST) -C examples/common/atari_netstream.cfg -D NETSTREAM_LINKED_HANDLER -D INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) $(SPEEDTEST_DEFINES) -o $@ examples/speedtest/atari_netstream_speedtest.c $(CA65_HANDLER_OBJ)

$(CA65_ATR_PSEUDOGAME_DIR)/autorun.sys: examples/pseudo_game_20hz/atari_pseudo_game_20hz.c $(CA65_HANDLER_OBJ) examples/common/atari_netstream.cfg | $(CA65_ATR_PSEUDOGAME_DIR) $(CA65_BUILD_DIR)
	$(CC65) $(CFLAGS) $(CFLAGS_EXTRA_CA65_PSEUDOGAME) -C examples/common/atari_netstream.cfg -D NETSTREAM_LINKED_HANDLER -D INPUT_BUFSIZE=$(NETSTREAM_INPUT_BUFSIZE) $(GAME_DEFINES) -o $@ examples/pseudo_game_20hz/atari_pseudo_game_20hz.c $(CA65_HANDLER_OBJ)

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

$(MADS_ATR_SPEEDTEST_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(MADS_ATR_SPEEDTEST_DIR)
	cp examples/dos/DOS.SYS $@

$(MADS_ATR_SPEEDTEST_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(MADS_ATR_SPEEDTEST_DIR)
	cp examples/dos/DUP.SYS $@

$(CA65_ATR_SPEEDTEST_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(CA65_ATR_SPEEDTEST_DIR)
	cp examples/dos/DOS.SYS $@

$(CA65_ATR_SPEEDTEST_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(CA65_ATR_SPEEDTEST_DIR)
	cp examples/dos/DUP.SYS $@

$(MADS_ATR_PSEUDOGAME_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(MADS_ATR_PSEUDOGAME_DIR)
	cp examples/dos/DOS.SYS $@

$(MADS_ATR_PSEUDOGAME_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(MADS_ATR_PSEUDOGAME_DIR)
	cp examples/dos/DUP.SYS $@

$(CA65_ATR_PSEUDOGAME_DIR)/DOS.SYS: examples/dos/DOS.SYS | $(CA65_ATR_PSEUDOGAME_DIR)
	cp examples/dos/DOS.SYS $@

$(CA65_ATR_PSEUDOGAME_DIR)/DUP.SYS: examples/dos/DUP.SYS | $(CA65_ATR_PSEUDOGAME_DIR)
	cp examples/dos/DUP.SYS $@

$(BUILD_DIR)/linux_netstream_chat: examples/chat/linux_netstream_chat.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/chat/linux_netstream_chat.c

$(BUILD_DIR)/linux_udp_sequence_server: examples/udp-sequence/linux_udp_sequence_server.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/udp-sequence/linux_udp_sequence_server.c

$(BUILD_DIR)/netstream_speed_server: examples/speedtest/netstream_speed_server.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/speedtest/netstream_speed_server.c

$(BUILD_DIR)/netstream_pseudo_game_server: examples/pseudo_game_20hz/server/netstream_pseudo_game_server.c | $(BUILD_DIR)
	$(CC) -O2 -Wall -Wextra -o $@ examples/pseudo_game_20hz/server/netstream_pseudo_game_server.c

$(MADS_ATR_CHAT_DIR) $(MADS_ATR_SEQ_DIR) $(MADS_ATR_SPEEDTEST_DIR) $(MADS_ATR_PSEUDOGAME_DIR): | $(MADS_BUILD_DIR)
	mkdir -p $@

$(CA65_ATR_CHAT_DIR) $(CA65_ATR_SEQ_DIR) $(CA65_ATR_SPEEDTEST_DIR) $(CA65_ATR_PSEUDOGAME_DIR): | $(CA65_BUILD_DIR)
	mkdir -p $@

$(MADS_BUILD_DIR)/atari_netstream_chat.atr: $(MADS_ATR_CHAT_DIR)/autorun.sys $(MADS_ATR_CHAT_DIR)/NSENGINE.OBX $(MADS_ATR_CHAT_DIR)/DOS.SYS $(MADS_ATR_CHAT_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_CHAT_DIR)

$(MADS_BUILD_DIR)/atari_udp_sequence.atr: $(MADS_ATR_SEQ_DIR)/autorun.sys $(MADS_ATR_SEQ_DIR)/NSENGINE.OBX $(MADS_ATR_SEQ_DIR)/DOS.SYS $(MADS_ATR_SEQ_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_SEQ_DIR)

$(MADS_BUILD_DIR)/atari_netstream_speedtest.atr: $(MADS_ATR_SPEEDTEST_DIR)/autorun.sys $(MADS_ATR_SPEEDTEST_DIR)/NSENGINE.OBX $(MADS_ATR_SPEEDTEST_DIR)/DOS.SYS $(MADS_ATR_SPEEDTEST_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_SPEEDTEST_DIR)

$(MADS_BUILD_DIR)/atari_pseudo_game_20hz.atr: $(MADS_ATR_PSEUDOGAME_DIR)/autorun.sys $(MADS_ATR_PSEUDOGAME_DIR)/NSENGINE.OBX $(MADS_ATR_PSEUDOGAME_DIR)/DOS.SYS $(MADS_ATR_PSEUDOGAME_DIR)/DUP.SYS | $(MADS_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(MADS_ATR_PSEUDOGAME_DIR)

$(CA65_BUILD_DIR)/atari_netstream_chat.atr: $(CA65_ATR_CHAT_DIR)/autorun.sys $(CA65_ATR_CHAT_DIR)/DOS.SYS $(CA65_ATR_CHAT_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_CHAT_DIR)

$(CA65_BUILD_DIR)/atari_udp_sequence.atr: $(CA65_ATR_SEQ_DIR)/autorun.sys $(CA65_ATR_SEQ_DIR)/DOS.SYS $(CA65_ATR_SEQ_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_SEQ_DIR)

$(CA65_BUILD_DIR)/atari_netstream_speedtest.atr: $(CA65_ATR_SPEEDTEST_DIR)/autorun.sys $(CA65_ATR_SPEEDTEST_DIR)/DOS.SYS $(CA65_ATR_SPEEDTEST_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_SPEEDTEST_DIR)

$(CA65_BUILD_DIR)/atari_pseudo_game_20hz.atr: $(CA65_ATR_PSEUDOGAME_DIR)/autorun.sys $(CA65_ATR_PSEUDOGAME_DIR)/DOS.SYS $(CA65_ATR_PSEUDOGAME_DIR)/DUP.SYS | $(CA65_BUILD_DIR)
	$(DIR2ATR) -b Dos25 720 $@ $(CA65_ATR_PSEUDOGAME_DIR)

clean:
	rm -rf $(BUILD_DIR)/*

.PHONY: all clean handlers mads ca65 linux speedtest pseudogame mads-handler ca65-handler mads-chat mads-udpseq mads-speedtest mads-pseudogame ca65-chat ca65-udpseq ca65-speedtest ca65-pseudogame
