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
;
;  Notes:
;  - Uses internal 32-byte input buffer and 32-byte output ring.
;  - PACTL motor line asserted for entire concurrent session.
;  - Future: replace with a FujiDevice netstream command; motor is the only cue for now.

		icl		'kerneldb.inc'
		icl		'hardware.inc'

;==========================================================================

INPUT_BUFSIZE = $20

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

		;force MIDI baud rate (31250): AUDF3=$21, AUDF4=$00
		lda		#$21
		sta		audf3
		lda		#$00
		sta		audf4

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

		;switch serial port to channel 4 async recv, channel 2 xmit
		lda		sskctl
		and		#$07
		ora		#$70
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

inputBuffer	.ds		INPUT_BUFSIZE
outputBuffer0	.ds		32

bss_end = outputBuffer0 + $20

;==========================================================================
; no auto-run
