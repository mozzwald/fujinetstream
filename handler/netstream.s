;	Altirra - Atari 800/800XL/5200 emulator
;	Replacement 850 Interface Firmware - R: Device Handler
;	Copyright (C) 2008-2017 Avery Lee
;
;	Copying and distribution of this file, with or without modification,
;	are permitted in any medium without royalty provided the copyright
;	notice and this notice are preserved.  This file is offered as-is,
;	without any warranty.
;
;  NETStream Concurrent Engine (stripped from Altirra 850 handler)
;  Keeps only concurrent-mode serial engine and IRQ handlers.
;  Removed: device handler glue, auto-install chain, non-concurrent I/O.
;
;  Notes:
;  - Uses internal 128-byte input buffer and 128-byte output ring.
;  - PACTL motor line asserted for entire concurrent session.
;
;  Converted from MADS to CA65 syntax.
;  Self-modifying-code labels (e.g. outLevel, inPtr, etc.) are kept as
;  file-scope globals so they can be referenced across routines.

		.include	"sio.inc"
		.include	"kerneldb.inc"
		.include	"hardware.inc"

;==========================================================================
; Exports to make functions visible from C.
.export _ns_begin_stream = NS_BeginConcurrent_Impl
.export _ns_end_stream = NS_EndConcurrent_Impl
.export _ns_get_version = NS_GetVersion_Impl
.export _ns_get_base = NS_GetBase_Impl
.export _ns_send_byte = NS_SendByte_Impl
.export _ns_recv_byte = NS_RecvByte_Impl
.export _ns_bytes_avail = NS_BytesAvail_Impl
.export _ns_get_status = NS_GetStatus_Impl
.export _ns_get_video_std = NS_GetVideoStd_Impl
.export _ns_init_netstream = NS_InitNetstream_Impl
.export _ns_get_final_flags = NS_GetFinalFlags_Impl
.export _ns_get_final_audf3 = NS_GetFinalAUDF3_Impl
.export _ns_get_final_audf4 = NS_GetFinalAUDF4_Impl

;==========================================================================

INPUT_BUFSIZE = $80
NETSTREAM_HOST_MAX = 61

siov	= $e459

;==========================================================================
; _ldahi: Load A with high byte of a 16-bit address (HIBUILD=0 default).
; If HIBUILD=1 is needed, change > to < below.

.macro _ldahi operand
		lda		#>operand
.endmacro

;==========================================================================

		.code

;==========================================================================
; API jump table
NS_BeginStream:
		jmp		NS_BeginConcurrent_Impl
NS_EndStream:
		jmp		NS_EndConcurrent_Impl
NS_GetVersion:
		jmp		NS_GetVersion_Impl
NS_GetBase:
		jmp		NS_GetBase_Impl
NS_SendByte:
		jmp		NS_SendByte_Impl
NS_RecvByte:
		jmp		NS_RecvByte_Impl
NS_BytesAvail:
		jmp		NS_BytesAvail_Impl
NS_GetStatus:
		jmp		NS_GetStatus_Impl
NS_GetVideoStd:
		jmp		NS_GetVideoStd_Impl
NS_InitNetstream:
		jmp		NS_InitNetstream_Impl
NS_GetFinalFlags:
		jmp		NS_GetFinalFlags_Impl
NS_GetFinalAUDF3:
		jmp		NS_GetFinalAUDF3_Impl
NS_GetFinalAUDF4:
		jmp		NS_GetFinalAUDF4_Impl

;==========================================================================
; NS_BeginStream
;
; Enters concurrent mode, installs IRQ vectors, and enables POKEY IRQs.
;
; Uses internal buffers (single stop bit only).
;
.proc NS_BeginConcurrent_Impl
		;NOTE: Future: add FujiDevice netstream command. For now, motor assert
		;is the only external cue that concurrent mode is active.
		jsr		DetectPALViaVCOUNT
		;set output idle and clear levels
		lda		#$ff
		sta		serialOutIdle

		lda		#0
		sta		outLevel
		sta		outIndex
		sta		serialOutHead
		ldx		#3
@clrerr:
		sta		serialErrors,x
		dex
		bpl		@clrerr

		;setup input buffer (internal)
		lda		#INPUT_BUFSIZE
		sta		serialInSize
		sta		serialInSpaceLo
		lda		#0
		sta		serialInSize+1
		sta		serialInSpaceHi

		lda		#<inputBuffer
		ldy		#>inputBuffer

		;(A,Y) -> inBufLo/inBufHi and inputPtr
		sta		inBufLo
		sta		inPtr
		sta		inReadPtr
		sty		inBufHi
		sty		inPtr+1
		sty		inReadPtr+1

		clc
		adc		serialInSize
		sta		inBufEndLo
		tya
		adc		serialInSize+1
		sta		inBufEndHi

		;setup output buffer
		lda		#<outputBuffer0
		sta		outBuf
		_ldahi	outputBuffer0
		sta		outBuf+1

		;init POKEY registers for serial mode (no SIO/850 modem commands)
		ldx		#8
@pokey_loop:
		lda		pokey_init,x
		sta		$d200,x
		dex
		bpl		@pokey_loop

		;apply configured AUDF3/AUDF4 (set by NS_InitNetstream)
		lda		NetstreamFinalAUDF3
		sta		audf3
		lda		NetstreamFinalAUDF4
		sta		audf4
		lda		#$28			;1.79MHz clock, join ch3+4
		sta		audctl

		;mark concurrent mode active
		sei
		lda		#1
		sta		serialConcurrentNum

		;assert motor line for concurrent session
		lda		#$34
		sta		pactl

		;select serial IRQ vectors (single stop bit only)
		ldy		#5

		;swap in interrupt handlers
		ldx		#5
@copy_loop:
		lda		vserin,x
		sta		serialVecSave,x
		lda		serialVecs,y
		sta		vserin,x
		dey
		dex
		bpl		@copy_loop

		jsr		SwapIrqVector

		;serial port timing from NetstreamFinalFlags:
		; 0x04 = TX clock source (0=internal ch4, 1=external)
		; 0x08 = RX clock source (0=internal async, 1=external)
		lda		sskctl
		and		#$0f
		lda		NetstreamFinalFlags
		and		#$0c
		beq		skctl_int_int		; RX int, TX int
		cmp		#$04
		beq		skctl_int_ext		; RX int, TX ext
		cmp		#$08
		beq		skctl_ext_int		; RX ext, TX int
		; RX ext, TX ext
		lda		#$00
		bne		skctl_apply
skctl_int_int:
		lda		#$30			; %011
		bne		skctl_apply
skctl_int_ext:
		lda		#$10			; %001
		bne		skctl_apply
skctl_ext_int:
		lda		#$40			; %100
skctl_apply:
		ora		sskctl
		sta		sskctl
		sta		skctl

		;enable serial input and output ready IRQs
		lda		pokmsk
		ora		#$30
		sta		pokmsk
		sta		irqen
		cli

		;all done
		ldy		#1
		rts
.endproc

;==========================================================================
; NS_EndStream
;
; Terminates concurrent I/O. Safe to call from IRQ.
;
; Used: A, X only; Y not touched
;
.proc NS_EndConcurrent_Impl
		;enter critical section
		php
		sei

		;check if concurrent I/O is active
		lda		serialConcurrentNum
		beq		not_active

		;disable serial interrupts
		lda		pokmsk
		and		#$c7
		sta		pokmsk
		sta		irqen

		;restore interrupt vectors
		ldx		#5
@restore:
		lda		serialVecSave,x
		sta		vserin,x
		dex
		bpl		@restore

		jsr		SwapIrqVector

		;deassert motor line
		lda		#$3c
		sta		pactl

		cli

		;clear concurrent index
		lda		#0
		sta		serialConcurrentNum

not_active:
		;leave critical section
		plp
		rts
.endproc

;==========================================================================
; NS_GetVersion
;
.proc NS_GetVersion_Impl
		lda		#$01
		rts
.endproc

;==========================================================================
; NS_GetBase
;
.proc NS_GetBase_Impl
		lda		#<NS_BeginStream
		ldx		#>NS_BeginStream
		rts
.endproc

;==========================================================================
; NS_SendByte
;
; Input: A = byte
; Output: C=0 success, C=1 full
;
.proc NS_SendByte_Impl
		php
		sei
		pha

		lda		outLevel
		cmp		#$80
		beq		full

		;check if output is idle
		bit		serialOutIdle
		bmi		output_idle

		;enqueue into ring
		pla
		ldx		serialOutHead
		sta		outputBuffer0,x
		inx
		txa
		and		#$7f
		sta		serialOutHead
		inc		outLevel
		clc
		plp
		rts

output_idle:
		pla
		sta		serout
		lsr		serialOutIdle
		clc
		plp
		rts

full:
		pla
		sec
		plp
		rts
.endproc

;==========================================================================
; NS_RecvByte
;
; Output: A = byte, C=0 success / C=1 empty
;
; Not wrapped in .proc because inReadPtr is a self-modifying-code label
; referenced externally from NS_BeginConcurrent_Impl.
;
NS_RecvByte_Impl:
		php
		sei

		lda		serialInSpaceLo
		cmp		serialInSize
		bne		NRB_not_empty
		lda		serialInSpaceHi
		cmp		serialInSize+1
		beq		NRB_empty

NRB_not_empty:
		lda		$ffff
inReadPtr = *-2
		pha

		;advance read pointer (inw inReadPtr)
		inc		inReadPtr
		bne		:+
		inc		inReadPtr+1
:
		lda		inReadPtr
		cmp		inBufEndLo
		bne		NRB_no_wrap
		lda		inReadPtr+1
		cmp		inBufEndHi
		bne		NRB_no_wrap
		lda		inBufLo
		sta		inReadPtr
		lda		inBufHi
		sta		inReadPtr+1

NRB_no_wrap:
		;increase space in buffer
		inc		serialInSpaceLo
		bne		NRB_space_done
		inc		serialInSpaceHi
NRB_space_done:
		pla
		clc
		plp
		rts

NRB_empty:
		sec
		plp
		rts

;==========================================================================
; NS_BytesAvail
;
; Output: A = low, X = high
;
.proc NS_BytesAvail_Impl
		php
		sei
		lda		serialInSize
		sec
		sbc		serialInSpaceLo
		tay
		lda		serialInSize+1
		sbc		serialInSpaceHi
		tax
		tya
		plp
		rts
.endproc

;==========================================================================
; NS_GetStatus
;
; Output: A = status, cleared on read
;
.proc NS_GetStatus_Impl
		php
		sei
		lda		serialErrors
		ldx		#0
		stx		serialErrors
		plp
		rts
.endproc

;==========================================================================
; NS_GetVideoStd
;
; Output: A = NetstreamVideoStd (0=NTSC, 1=PAL)
;
.proc NS_GetVideoStd_Impl
		lda		NetstreamVideoStd
		rts
.endproc

;==========================================================================
; NS_InitNetstream
;
; Calling convention:
;   A/X = port (swapped, low/high)
;   C stack (c_sp at $82): nominal_baud (lo/hi), flags, hostname ptr (lo/hi)
;
; Flags bit 0x10 is set/cleared based on VCOUNT PAL detection.
; Payload: hostname\0 [flags] [audf3]
;
.proc NS_InitNetstream_Impl
		php
		sei

		; save port from A/X
		sta		NetstreamPortLo
		stx		NetstreamPortHi

		; decode cc65 fastcall args from C stack (c_sp at $82)
		ldy		#0
		lda		($82),y			; nominal lo
		sta		NetstreamNominalBaudLo
		iny
		lda		($82),y			; nominal hi
		sta		NetstreamNominalBaudHi
		iny
		lda		($82),y			; flags
		sta		NetstreamFinalFlags
		iny
		lda		($82),y			; host lo
		sta		hostPtr
		iny
		lda		($82),y			; host hi
		sta		hostPtr+1

		lda		NetstreamNominalBaudLo
		ldx		NetstreamNominalBaudHi
		jsr		LookupBaudFromNominal
		bcc		lookup_ok
		jmp		init_fail
lookup_ok:
		; apply PAL flag (0x10) after flags are known
		jsr		DetectPALViaVCOUNT
		lda		NetstreamFinalFlags
		ldx		NetstreamVideoStd
		beq		ntsc_flag
		ora		#$10
		bne		store_flags
ntsc_flag:
		and		#$ef
store_flags:
		sta		NetstreamFinalFlags
		; UDP sequencing flag (0x20) is only valid for UDP
		; If TCP is selected (bit 0x01), clear sequencing.
		lda		NetstreamFinalFlags
		and		#$01
		beq		seq_ok
		lda		NetstreamFinalFlags
		and		#$df
		sta		NetstreamFinalFlags
seq_ok:

		; build payload buffer: hostname\0 flags audf3 (pad to 64 bytes)
		ldy		#0
copy_host:
		lda		$ffff,y
hostPtr = *-2
		sta		NetstreamPayloadBuf,y
		beq		append_flags
		iny
		cpy		#NETSTREAM_HOST_MAX
		bcc		copy_host
		; force NUL if maxed
		lda		#0
		sta		NetstreamPayloadBuf,y

append_flags:
		; y = index of NUL terminator
		iny
		lda		NetstreamFinalFlags
		sta		NetstreamPayloadBuf,y
		iny
		lda		NetstreamFinalAUDF3
		sta		NetstreamPayloadBuf,y
		iny
		; pad out to 64 bytes
pad_loop:
		cpy		#64
		bcs		payload_done
		lda		#0
		sta		NetstreamPayloadBuf,y
		iny
		bne		pad_loop
payload_done:
		lda		#64
		sta		NetstreamPayloadLen

		; setup SIO DCB for $70/$F0 enable_netstream
		lda		#$70
		sta		ddevic
		lda		#1
		sta		dunit
		lda		#$f0
		sta		dcomnd
		lda		#$80
		sta		dstats
		lda		#<NetstreamPayloadBuf
		sta		dbuflo
		lda		#>NetstreamPayloadBuf
		sta		dbufhi
		lda		NetstreamPayloadLen
		sta		dbytlo
		lda		#0
		sta		dbythi
		lda		NetstreamPortLo
		sta		daux1
		lda		NetstreamPortHi
		sta		daux2
		lda		#$0f
		sta		dtimlo
		lda		#0
		sta		dtimlo+1

		cli
		jsr		siov
		sei

		; program POKEY for stream mode with selected AUDF3/AUDF4
		ldx		#8
@pokey_loop:
		lda		pokey_init,x
		sta		$d200,x
		dex
		bpl		@pokey_loop
		lda		NetstreamFinalAUDF3
		sta		audf3
		lda		NetstreamFinalAUDF4
		sta		audf4
		lda		#$28			;1.79MHz clock, join ch3+4
		sta		audctl

		lda		#0
		plp
		clc
		rts
init_fail:
		; indicate failure (carry set)
		lda		#1
		plp
		sec
		rts
.endproc

;==========================================================================
; NS_GetFinalFlags/AUDF3/AUDF4
;
.proc NS_GetFinalFlags_Impl
		lda		NetstreamFinalFlags
		rts
.endproc

.proc NS_GetFinalAUDF3_Impl
		lda		NetstreamFinalAUDF3
		rts
.endproc

.proc NS_GetFinalAUDF4_Impl
		lda		NetstreamFinalAUDF4
		rts
.endproc

;==========================================================================
; LookupBaudFromNominal
;
; Input: A = nominal baud lo, X = nominal baud hi
; Output: NetstreamFinalAUDF3/AUDF4 set, C=0 on success, C=1 on fail
;
.proc LookupBaudFromNominal
		sta		NetstreamNominalBaudLo
		stx		NetstreamNominalBaudHi
		ldx		#0
scan_nominal:
		lda		BaudTable,x
		ora		BaudTable+1,x
		beq		baud_fail
		lda		BaudTable,x
		cmp		NetstreamNominalBaudLo
		bne		next_entry
		lda		BaudTable+1,x
		cmp		NetstreamNominalBaudHi
		bne		next_entry
		; matched entry: select NTSC or PAL pair
		lda		NetstreamVideoStd
		beq		use_ntsc
		lda		BaudTable+4,x
		sta		NetstreamFinalAUDF3
		lda		BaudTable+5,x
		sta		NetstreamFinalAUDF4
		clc
		rts
use_ntsc:
		lda		BaudTable+2,x
		sta		NetstreamFinalAUDF3
		lda		BaudTable+3,x
		sta		NetstreamFinalAUDF4
		clc
		rts
next_entry:
		txa
		clc
		adc		#6
		tax
		bne		scan_nominal
baud_fail:
		sec
		rts
.endproc

BaudTable:
		; nominal_lo, nominal_hi, ntsc_audf3, ntsc_audf4, pal_audf3, pal_audf4
		.byte	$2c,$01,159,11,132,11	; 300
		.byte	$58,$02,204,5,190,5		; 600
		.byte	$ee,$02,162,4,151,4		; 750
		.byte	$b0,$04,226,2,219,2		; 1200
		.byte	$60,$09,109,1,106,1		; 2400
		.byte	$c0,$12,179,0,177,0		; 4800
		.byte	$80,$25,86,0,85,0		; 9600
		.byte	$00,$4b,39,0,39,0		; 19200
		.byte	$12,$7a,21,0,21,0		; 31250
		.byte	$00,$96,16,0,16,0		; 38400
		.byte	$34,$9e,15,0,15,0		; ~40500
		.byte	$58,$a6,14,0,14,0		; ~42600
		.byte	$9c,$ae,13,0,13,0		; ~44700
		.byte	$fc,$b7,12,0,12,0		; ~47100
		.byte	$24,$c2,11,0,11,0		; ~49700
		.byte	$88,$cd,10,0,10,0		; ~52600
		.byte	$5c,$da,9,0,9,0			; ~55900
		.byte	$00,$e1,8,0,8,0			; 57600
		.byte	$78,$f8,7,0,7,0			; ~63600
		.byte	$90,$0b,6,0,6,0			; ~68400
		.byte	$18,$12,5,0,5,0			; ~74200
		.byte	$24,$1f,4,0,4,0			; ~81400
		.byte	$94,$23,3,0,3,0			; ~90500
		.byte	$70,$8d,2,0,2,0			; ~102000
		.byte	$30,$cd,1,0,1,0			; ~118000
		.byte	$30,$ec,0,0,0,0			; ~126000
		.byte	0,0

;==========================================================================
; DetectPALViaVCOUNT
;
; VCOUNT is a scanline/2 counter. NTSC tops out around ~130, PAL around ~155.
; We treat >=150 as PAL. This loop is bounded to avoid hangs.
;
.proc DetectPALViaVCOUNT
		lda		vcount
		sta		NetstreamVCountPrev
		sta		NetstreamVCountMax
		ldx		#$ff
		ldy		#$ff
loop:
		lda		vcount
		cmp		NetstreamVCountMax
		bcc		no_max
		sta		NetstreamVCountMax
no_max:
		cmp		NetstreamVCountPrev
		bcc		wrapped
		sta		NetstreamVCountPrev

		dey
		bne		loop
		dex
		bne		loop

wrapped:
		lda		NetstreamVCountMax
		cmp		#150
		bcc		ntsc
		lda		#1
		bne		store
ntsc:
		lda		#0
store:
		sta		NetstreamVideoStd
		rts
.endproc

;==========================================================================
;==========================================================================
; Serial input ready IRQ handler.
;
; Not wrapped in .proc because SMC labels (serialInSpaceLo, inPtr, etc.)
; are referenced from other routines (NS_BeginConcurrent_Impl, NS_RecvByte_Impl).
;
SerialInputIrqHandler:
		;check if we have space in the buffer
		lda		#0
serialInSpaceLo = *-1
		bne		SIH_not_full
		lda		#0
serialInSpaceHi = *-1
		beq		SIH_is_full

SIH_not_full:
		;read char and store it in the buffer
		lda		serin
		sta		$ffff
inPtr = *-2

		;bump write (tail) pointer (inw inPtr)
		inc		inPtr
		bne		:+
		inc		inPtr+1
:
		lda		inPtr
		cmp		#0
inBufEndLo = *-1
		bne		SIH_no_wrap
		lda		inPtr+1
		cmp		#0
inBufEndHi = *-1
		bne		SIH_no_wrap
		lda		#0
inBufLo = *-1
		sta		inPtr
		lda		#0
inBufHi = *-1
		sta		inPtr+1
SIH_no_wrap:
		;decrement space level in buffer (sne:dec / dec pattern)
		lda		serialInSpaceLo
		bne		:+
		dec		serialInSpaceHi
:
		dec		serialInSpaceLo

SIH_xit:
		pla
		rti

SIH_is_full:
		;set overflow error status (bit 4)
		txa
		pha
		ldx		serialConcurrentNum
		lda		#$10
		ora		serialErrors-1,x
		sta		serialErrors-1,x
		pla
		tax
		jmp		SIH_xit

;==========================================================================
; Serial output ready IRQ handler for one stop bit.
;
; Not wrapped in .proc because SMC labels (outLevel, outIndex, outBuf)
; are referenced from NS_BeginConcurrent_Impl and NS_SendByte_Impl.
;
SerialOutputIrqHandler:
		lda		#0
outLevel = *-1
		beq		SOH_is_empty
		dec		outLevel
		txa
		pha
		ldx		#0
outIndex = *-1
		lda		$ffff,x
outBuf = *-2
		sta		serout
		inx
		txa
		and		#$7f
		sta		outIndex
		pla
		tax
SOH_xit:
		pla
		rti
SOH_is_empty:
		sec
		ror		serialOutIdle
		bne		SOH_xit

; Serial output complete IRQ handler (same entry as output handler exit)
SerialCompleteIrqHandler = SOH_xit

;==========================================================================
; IRQ handler used during concurrent I/O.
;
; Not wrapped in .proc because chain_addr is referenced from SwapIrqVector.
;
IrqHandler:
		;check if the Break key IRQ is active
		bit		irqst
		bpl		IH_is_break

		;chain to old IRQ handler
		jmp		IrqHandler
chain_addr = * - 2

IH_is_break:
		;ack the break IRQ and return
		pha
		lda		#$7f
		sta		irqen
		lda		pokmsk
		sta		irqen
		pla
		rti

;==========================================================================
; Exchange the IRQ vector at VIMIRQ with the IRQ save/chain address.
;
.proc SwapIrqVector
		ldx		#1
loop:
		lda		vimirq,x
		pha
		lda		chain_addr,x
		sta		vimirq,x
		pla
		sta		chain_addr,x
		dex
		bpl		loop
		rts
.endproc

;==========================================================================
serialVecs:
		.word	SerialInputIrqHandler
		.word	SerialOutputIrqHandler
		.word	SerialCompleteIrqHandler

;==========================================================================
; POKEY init defaults (AUDC/AUDCTL/etc). AUDF3/AUDF4 overridden below.
pokey_init:
		.byte	$00		; audf1
		.byte	$00		; audc1
		.byte	$00		; audf2
		.byte	$00		; audc2
		.byte	$00		; audf3 (overridden)
		.byte	$00		; audc3
		.byte	$00		; audf4 (overridden)
		.byte	$00		; audc4
		.byte	$00		; audctl

;==========================================================================
; BSS

		.bss

serialOutIdle:			.res	1
serialInSize:			.res	2
serialVecSave:			.res	6
serialErrors:			.res	4
serialConcurrentNum:	.res	1
serialOutHead:			.res	1

NetstreamVideoStd:		.res	1		;0=NTSC, 1=PAL
NetstreamVCountMax:		.res	1
NetstreamVCountPrev:	.res	1
NetstreamFinalFlags:	.res	1
NetstreamFinalAUDF3:	.res	1
NetstreamFinalAUDF4:	.res	1
NetstreamPayloadLen:	.res	1
NetstreamPortLo:		.res	1
NetstreamPortHi:		.res	1
NetstreamNominalBaudLo:	.res	1
NetstreamNominalBaudHi:	.res	1

inputBuffer:			.res	INPUT_BUFSIZE
outputBuffer0:			.res	128
NetstreamPayloadBuf:	.res	64

