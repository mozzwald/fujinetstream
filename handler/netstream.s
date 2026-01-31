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
;  API jump table at BASEADDR (JMP absolute, 3 bytes each):
;    BASEADDR = build-time constant (Makefile HANDLER_BASE)
;    +0   NS_BeginConcurrent  Start concurrent mode, install IRQs, assert motor
;    +3   NS_EndConcurrent    Stop concurrent mode, restore IRQs, deassert motor
;    +6   NS_GetVersion       Return version byte in A
;    +9   NS_GetBase          Return BASEADDR in A (lo), X (hi)
;    +12  NS_SendByte         Enqueue A to output, C=0 ok / C=1 full
;    +15  NS_RecvByte         Dequeue to A, C=0 ok / C=1 empty
;    +18  NS_BytesAvail       Return RX count in A (lo), X (hi)
;    +21  NS_GetStatus        Return sticky status in A (clear on read)
;    +24  NS_GetVideoStd      Return 0=NTSC, 1=PAL
;    +27  NS_GetVCountMax     Return max VCOUNT observed (debug)
;    +30  NS_InitNetstream    Send $70/$F0 enable with hostname/flags/baud
;    +33  NS_GetFinalFlags    Return final flags byte (PAL bit applied)
;    +36  NS_GetFinalAUDF3    Return final AUDF3
;    +39  NS_GetFinalAUDF4    Return final AUDF4
;    +42  NS_GetNominalBaudLo Return captured nominal baud lo (debug)
;    +45  NS_GetNominalBaudHi Return captured nominal baud hi (debug)
;    +48  NS_GetDebugB0       Return debug byte 0
;    +51  NS_GetDebugB1       Return debug byte 1
;    +54  NS_GetDebugB2       Return debug byte 2
;    +57  NS_GetDebugB3       Return debug byte 3
;    +60  NS_GetDebugB4       Return debug byte 4
;    +63  NS_GetDebugB5       Return debug byte 5
;    +66  NS_GetSioStatus     Return last SIO status (Y)
;    +69  NS_GetDcbDev        Return DDEVIC
;    +72  NS_GetDcbCmd        Return DCOMND
;    +75  NS_GetDcbStat       Return DSTATS
;    +78  NS_GetDcbDbufLo     Return DBUFLO
;    +81  NS_GetDcbDbufHi     Return DBUFHI
;    +84  NS_GetDcbDbytLo     Return DBYTLO
;    +87  NS_GetDcbDbytHi     Return DBYTHI
;    +90  NS_GetDcbAux1       Return DAUX1
;    +93  NS_GetDcbAux2       Return DAUX2
;    +96  NS_GetDcbTimLo      Return DTIMLO
;
;  Notes:
;  - Uses internal 32-byte input buffer and 32-byte output ring.
;  - PACTL motor line asserted for entire concurrent session.
;  - Future: replace with a FujiDevice netstream command; motor is the only cue for now.

		icl		'sio.inc'
		icl		'kerneldb.inc'
		icl		'hardware.inc'

;==========================================================================

INPUT_BUFSIZE = $20
NETSTREAM_HOST_MAX = 61

siov	= $e459

;==========================================================================

.macro _hiop opcode adrmode operand
		.if :adrmode!='#'
		.error "Immediate addressing mode must be used with hi-opcode"
		.endif
		.if HIBUILD
		:opcode <:operand
		.else
		:opcode >:operand
		.endif
.endm

.macro _ldahi adrmode operand " "
		_hiop lda :adrmode :operand
.endm

.macro _ldxhi adrmode operand " "
		_hiop ldx :adrmode :operand
.endm

.macro _ldyhi adrmode operand " "
		_hiop ldy :adrmode :operand
.endm

;==========================================================================

		org		BASEADDR

;==========================================================================
; API jump table
NS_BeginConcurrent:
		jmp		NS_BeginConcurrent_Impl
NS_EndConcurrent:
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
NS_GetVCountMax:
		jmp		NS_GetVCountMax_Impl
NS_InitNetstream:
		jmp		NS_InitNetstream_Impl
NS_GetFinalFlags:
		jmp		NS_GetFinalFlags_Impl
NS_GetFinalAUDF3:
		jmp		NS_GetFinalAUDF3_Impl
NS_GetFinalAUDF4:
		jmp		NS_GetFinalAUDF4_Impl
NS_GetNominalBaudLo:
		jmp		NS_GetNominalBaudLo_Impl
NS_GetNominalBaudHi:
		jmp		NS_GetNominalBaudHi_Impl
NS_GetDebugB0:
		jmp		NS_GetDebugB0_Impl
NS_GetDebugB1:
		jmp		NS_GetDebugB1_Impl
NS_GetDebugB2:
		jmp		NS_GetDebugB2_Impl
NS_GetDebugB3:
		jmp		NS_GetDebugB3_Impl
NS_GetDebugB4:
		jmp		NS_GetDebugB4_Impl
NS_GetDebugB5:
		jmp		NS_GetDebugB5_Impl
NS_GetSioStatus:
		jmp		NS_GetSioStatus_Impl
NS_GetDcbDev:
		jmp		NS_GetDcbDev_Impl
NS_GetDcbCmd:
		jmp		NS_GetDcbCmd_Impl
NS_GetDcbStat:
		jmp		NS_GetDcbStat_Impl
NS_GetDcbDbufLo:
		jmp		NS_GetDcbDbufLo_Impl
NS_GetDcbDbufHi:
		jmp		NS_GetDcbDbufHi_Impl
NS_GetDcbDbytLo:
		jmp		NS_GetDcbDbytLo_Impl
NS_GetDcbDbytHi:
		jmp		NS_GetDcbDbytHi_Impl
NS_GetDcbAux1:
		jmp		NS_GetDcbAux1_Impl
NS_GetDcbAux2:
		jmp		NS_GetDcbAux2_Impl
NS_GetDcbTimLo:
		jmp		NS_GetDcbTimLo_Impl

;==========================================================================
; NS_BeginConcurrent
;
; Enters concurrent mode, installs IRQ vectors, and enables POKEY IRQs.
;
; Uses internal buffers, config in NS_Config (bit 7 = 2 stop bits).
;
.proc NS_BeginConcurrent_Impl
		;NOTE: Future: add FujiDevice netstream command. For now, motor assert
		;is the only external cue that concurrent mode is active.
		jsr		DetectPALViaVCOUNT
		;set output idle and clear levels
		lda		#$ff
		sta		serialOutIdle

		lda		#0
		sta		SerialOutputIrqHandler.outLevel
		sta		SerialOutputIrqHandler.outIndex
		sta		serialOutHead
		ldx		#3
		sta:rpl	serialErrors,x-

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
		sta		SerialInputIrqHandler.inBufLo
		sta		SerialInputIrqHandler.inPtr
		sta		NS_RecvByte_Impl.inReadPtr
		sty		SerialInputIrqHandler.inBufHi
		sty		SerialInputIrqHandler.inPtr+1
		sty		NS_RecvByte_Impl.inReadPtr+1

		clc
		adc		serialInSize
		sta		SerialInputIrqHandler.inBufEndLo
		tya
		adc		serialInSize+1
		sta		SerialInputIrqHandler.inBufEndHi

		;setup output buffer
		lda		#<outputBuffer0
		sta		SerialOutputIrqHandler.outBuf
		_ldahi	#outputBuffer0
		sta		SerialOutputIrqHandler.outBuf+1

		;init POKEY registers for serial mode (no SIO/850 modem commands)
		ldx		#8
		mva:rpl	pokey_init,x $d200,x-

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

		;select one stop bit serial routines
		ldy		#5
		lda		#0
		sta		serial2SBMode

		;swap in interrupt handlers
		ldx		#5
copy_loop:
		mva		vserin,x serialVecSave,x
		mva		serialVecs,y vserin,x
		dey
		dex
		bpl		copy_loop

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
.endp

;==========================================================================
; NS_EndConcurrent
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
		mva:rpl	serialVecSave,x vserin,x-

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
.endp

;==========================================================================
; NS_GetVersion
;
.proc NS_GetVersion_Impl
		lda		#$01
		rts
.endp

;==========================================================================
; NS_GetBase
;
.proc NS_GetBase_Impl
		lda		#<BASEADDR
		ldx		#>BASEADDR
		rts
.endp

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

		lda		SerialOutputIrqHandler.outLevel
		cmp		#$20
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
		and		#$1f
		sta		serialOutHead
		inc		SerialOutputIrqHandler.outLevel
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
.endp

;==========================================================================
; NS_RecvByte
;
; Output: A = byte, C=0 success / C=1 empty
;
.proc NS_RecvByte_Impl
		php
		sei

		lda		serialInSpaceLo
		cmp		serialInSize
		bne		not_empty
		lda		serialInSpaceHi
		cmp		serialInSize+1
		beq		empty

not_empty:
		lda		$ffff
inReadPtr = *-2
		pha

		;advance read pointer
		inw		inReadPtr
		lda		inReadPtr
		cmp		SerialInputIrqHandler.inBufEndLo
		bne		no_wrap
		lda		inReadPtr+1
		cmp		SerialInputIrqHandler.inBufEndHi
		bne		no_wrap
		mva		SerialInputIrqHandler.inBufLo inReadPtr
		mva		SerialInputIrqHandler.inBufHi inReadPtr+1

no_wrap:
		;increase space in buffer
		inc		serialInSpaceLo
		bne		space_done
		inc		serialInSpaceHi
space_done:
		pla
		clc
		plp
		rts

empty:
		sec
		plp
		rts
.endp

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
.endp

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
.endp

;==========================================================================
; NS_GetVideoStd
;
; Output: A = NetstreamVideoStd (0=NTSC, 1=PAL)
;
.proc NS_GetVideoStd_Impl
		lda		NetstreamVideoStd
		rts
.endp

;==========================================================================
; NS_GetVCountMax
;
; Output: A = NetstreamVCountMax
;
.proc NS_GetVCountMax_Impl
		lda		NetstreamVCountMax
		rts
.endp

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
		ora		#$02			; force REGISTER bit on for now
		sta		NetstreamFinalFlags

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
		sta		NetstreamDcbDev
		lda		#1
		sta		dunit
		lda		#$f0
		sta		dcomnd
		sta		NetstreamDcbCmd
		lda		#$80
		sta		dstats
		sta		NetstreamDcbStat
		lda		#<NetstreamPayloadBuf
		sta		dbuflo
		sta		NetstreamDcbDbufLo
		lda		#>NetstreamPayloadBuf
		sta		dbufhi
		sta		NetstreamDcbDbufHi
		lda		NetstreamPayloadLen
		sta		dbytlo
		sta		NetstreamDcbDbytLo
		lda		#0
		sta		dbythi
		sta		NetstreamDcbDbytHi
		lda		NetstreamPortLo
		sta		daux1
		sta		NetstreamDcbAux1
		lda		NetstreamPortHi
		sta		daux2
		sta		NetstreamDcbAux2
		lda		#$0f
		sta		dtimlo
		sta		NetstreamDcbTimLo
		lda		#0
		sta		dtimlo+1

		cli
		jsr		siov
		sty		NetstreamSioStatus
		sei

		; program POKEY for stream mode with selected AUDF3/AUDF4
		ldx		#8
		mva:rpl	pokey_init,x $d200,x-
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
.endp

;==========================================================================
; NS_GetFinalFlags/AUDF3/AUDF4
;
.proc NS_GetFinalFlags_Impl
		lda		NetstreamFinalFlags
		rts
.endp

.proc NS_GetFinalAUDF3_Impl
		lda		NetstreamFinalAUDF3
		rts
.endp

.proc NS_GetFinalAUDF4_Impl
		lda		NetstreamFinalAUDF4
		rts
.endp

.proc NS_GetNominalBaudLo_Impl
		lda		NetstreamNominalBaudLo
		rts
.endp

.proc NS_GetNominalBaudHi_Impl
		lda		NetstreamNominalBaudHi
		rts
.endp

.proc NS_GetDebugB0_Impl
		lda		NetstreamDebugB0
		rts
.endp

.proc NS_GetDebugB1_Impl
		lda		NetstreamDebugB1
		rts
.endp

.proc NS_GetDebugB2_Impl
		lda		NetstreamDebugB2
		rts
.endp

.proc NS_GetDebugB3_Impl
		lda		NetstreamDebugB3
		rts
.endp

.proc NS_GetDebugB4_Impl
		lda		NetstreamDebugB4
		rts
.endp

.proc NS_GetDebugB5_Impl
		lda		NetstreamDebugB5
		rts
.endp

.proc NS_GetSioStatus_Impl
		lda		NetstreamSioStatus
		rts
.endp

.proc NS_GetDcbDev_Impl
		lda		NetstreamDcbDev
		rts
.endp

.proc NS_GetDcbCmd_Impl
		lda		NetstreamDcbCmd
		rts
.endp

.proc NS_GetDcbStat_Impl
		lda		NetstreamDcbStat
		rts
.endp

.proc NS_GetDcbDbufLo_Impl
		lda		NetstreamDcbDbufLo
		rts
.endp

.proc NS_GetDcbDbufHi_Impl
		lda		NetstreamDcbDbufHi
		rts
.endp

.proc NS_GetDcbDbytLo_Impl
		lda		NetstreamDcbDbytLo
		rts
.endp

.proc NS_GetDcbDbytHi_Impl
		lda		NetstreamDcbDbytHi
		rts
.endp

.proc NS_GetDcbAux1_Impl
		lda		NetstreamDcbAux1
		rts
.endp

.proc NS_GetDcbAux2_Impl
		lda		NetstreamDcbAux2
		rts
.endp

.proc NS_GetDcbTimLo_Impl
		lda		NetstreamDcbTimLo
		rts
.endp

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
.endp

BaudTable:
		; nominal, nominal_hi, ntsc_audf3, ntsc_audf4, pal_audf3, pal_audf4
		dta		$2c,$01,159,11,132,11	; 300
		dta		$58,$02,204,5,190,5		; 600
		dta		$ee,$02,162,4,151,4		; 750
		dta		$b0,$04,226,2,219,2		; 1200
		dta		$60,$09,109,1,106,1		; 2400
		dta		$c0,$12,179,0,177,0		; 4800
		dta		$80,$25,86,0,85,0		; 9600
		dta		$00,$4b,39,0,39,0		; 19200
		dta		$12,$7a,21,0,21,0		; 31250
		dta		$00,$96,16,0,16,0		; 38400
		dta		$34,$9e,15,0,15,0		; ~40500
		dta		$58,$a6,14,0,14,0		; ~42600
		dta		$9c,$ae,13,0,13,0		; ~44700
		dta		$fc,$b7,12,0,12,0		; ~47100
		dta		$24,$c2,11,0,11,0		; ~49700
		dta		$88,$cd,10,0,10,0		; ~52600
		dta		$5c,$da,9,0,9,0		; ~55900
		dta		$00,$e1,8,0,8,0		; 57600
		dta		$78,$f8,7,0,7,0		; ~63600
		dta		$90,$0b,6,0,6,0		; ~68400
		dta		$18,$12,5,0,5,0		; ~74200
		dta		$24,$1f,4,0,4,0		; ~81400
		dta		$94,$23,3,0,3,0		; ~90500
		dta		$70,$8d,2,0,2,0		; ~102000
		dta		$30,$cd,1,0,1,0		; ~118000
		dta		$30,$ec,0,0,0,0		; ~126000
		dta		0,0

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
.endp

;==========================================================================
;==========================================================================
;
;==========================================================================
.proc SerialInputIrqHandler
		;check if we have space in the buffer
		lda		#0
.def :serialInSpaceLo = *-1
		bne		not_full
		lda		#0
.def :serialInSpaceHi = *-1
		beq		is_full

not_full:
		;read char and store it in the buffer
		lda		serin
		sta		$ffff
inPtr = *-2

		;bump write (tail) pointer
		inw		inPtr
		lda		inPtr
		cmp		#0
inBufEndLo = *-1
		bne		no_wrap
		lda		inPtr+1
		cmp		#0
inBufEndHi = *-1
		bne		no_wrap
		lda		#0
inBufLo = *-1
		sta		inPtr
		lda		#0
inBufHi = *-1
		sta		inPtr+1
no_wrap:
		;decrement space level in buffer
		lda		serialInSpaceLo
		sne:dec	serialInSpaceHi
		dec		serialInSpaceLo

xit:
		pla
		rti

is_full:
		;set overflow error status (bit 4)
		txa
		pha
		ldx		serialConcurrentNum
		lda		#$10
		ora		serialErrors-1,x
		sta		serialErrors-1,x
		pla
		tax
		jmp		xit
.endp

;==========================================================================
; Serial output ready IRQ handler for two stop bits.
;
.proc SerialOutputIrqHandler2SB
		;turn on complete IRQ
		lda		pokmsk
		ora		#$08
		sta		pokmsk
		sta		irqen
		pla
		rti
.endp

;==========================================================================
; Serial output complete IRQ handler for two stop bits.
;
.proc SerialCompleteIrqHandler2SB
		;turn off complete IRQ
		lda		pokmsk
		and		#$f7
		sta		pokmsk
		sta		irqen

		;fall through
.endp

;==========================================================================
; Serial output ready IRQ handler for one stop bit.
;
.proc SerialOutputIrqHandler
		lda		#0
outLevel = *-1
		beq		is_empty
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
		and		#$1f
		sta		outIndex
		pla
		tax
xit:
.def :SerialCompleteIrqHandler = *
		pla
		rti
is_empty:
		sec
		ror		serialOutIdle
		bne		xit
.endp

;==========================================================================
; IRQ handler used during concurrent I/O.
;
.proc IrqHandler
		;check if the Break key IRQ is active
		bit		irqst
		bpl		is_break

		;chain to old IRQ handler
		jmp		IrqHandler
chain_addr = * - 2

is_break:
		;ack the break IRQ and return
		pha
		lda		#$7f
		sta		irqen
		lda		pokmsk
		sta		irqen
		pla
		rti
.endp

;==========================================================================
; Exchange the IRQ vector at VIMIRQ with the IRQ save/chain address.
;
.proc SwapIrqVector
		ldx		#1
loop:
		lda		vimirq,x
		pha
		lda		IrqHandler.chain_addr,x
		sta		vimirq,x
		pla
		sta		IrqHandler.chain_addr,x
		dex
		bpl		loop
		rts
.endp

;==========================================================================
serialVecs:
		dta		a(SerialInputIrqHandler)
		dta		a(SerialOutputIrqHandler)
		dta		a(SerialCompleteIrqHandler)

serialVecs2SB:
		dta		a(SerialInputIrqHandler)
		dta		a(SerialOutputIrqHandler2SB)
		dta		a(SerialCompleteIrqHandler2SB)

;==========================================================================
; POKEY init defaults (AUDC/AUDCTL/etc). AUDF3/AUDF4 overridden below.
pokey_init:
		dta		$00		; audf1
		dta		$00		; audc1
		dta		$00		; audf2
		dta		$00		; audc2
		dta		$00		; audf3 (overridden)
		dta		$00		; audc3
		dta		$00		; audf4 (overridden)
		dta		$00		; audc4
		dta		$00		; audctl

;==========================================================================
; Minimal BSS
bss_start = *

		org		bss_start
serialOutIdle	.ds		1
serialInSize	.ds		2
serialVecSave	.ds		6
serialErrors	.ds		4
serial2SBMode	.ds		1
serialConcurrentNum	.ds	1
serialOutHead	.ds		1

NS_Config	.ds		1		;config byte for concurrent mode (bit 7 = 2 stop bits)
NetstreamVideoStd	.ds	1		;0=NTSC, 1=PAL
NetstreamVCountMax	.ds	1
NetstreamVCountPrev	.ds	1
NetstreamFinalFlags	.ds	1
NetstreamFinalAUDF3	.ds	1
NetstreamFinalAUDF4	.ds	1
NetstreamPayloadLen	.ds	1
NetstreamPortLo	.ds	1
NetstreamPortHi	.ds	1
NetstreamNominalBaudLo	.ds	1
NetstreamNominalBaudHi	.ds	1
NetstreamDebugB0	.ds	1
NetstreamDebugB1	.ds	1
NetstreamDebugB2	.ds	1
NetstreamDebugB3	.ds	1
NetstreamDebugB4	.ds	1
NetstreamDebugB5	.ds	1
NetstreamSioStatus	.ds	1
NetstreamDcbDev	.ds	1
NetstreamDcbCmd	.ds	1
NetstreamDcbStat	.ds	1
NetstreamDcbDbufLo	.ds	1
NetstreamDcbDbufHi	.ds	1
NetstreamDcbDbytLo	.ds	1
NetstreamDcbDbytHi	.ds	1
NetstreamDcbAux1	.ds	1
NetstreamDcbAux2	.ds	1
NetstreamDcbTimLo	.ds	1

inputBuffer	.ds		INPUT_BUFSIZE
outputBuffer0	.ds		32
NetstreamPayloadBuf	.ds	64

bss_end = NetstreamPayloadBuf + 64

;==========================================================================
; no auto-run
