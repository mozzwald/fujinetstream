; cc65/ca65 wrappers for NETStream engine jump table

		.export _ns_begin
		.export _ns_end
		.export _ns_get_version
		.export _ns_get_base
		.export _ns_send_byte
		.export _ns_recv_byte
		.export _ns_bytes_avail
		.export _ns_get_status
		.export _ns_get_video_std
		.export _ns_get_vcount_max
		.export _ns_init_netstream
		.export _ns_get_final_flags
		.export _ns_get_final_audf3
		.export _ns_get_final_audf4
		.export _ns_get_nominal_baud_lo
		.export _ns_get_nominal_baud_hi
		.export _ns_get_debug_b0
		.export _ns_get_debug_b1
		.export _ns_get_debug_b2
		.export _ns_get_debug_b3
		.export _ns_get_debug_b4
		.export _ns_get_debug_b5
		.export _ns_get_sio_status
		.export _ns_get_dcb_dev
		.export _ns_get_dcb_cmd
		.export _ns_get_dcb_stat
		.export _ns_get_dcb_dbuf_lo
		.export _ns_get_dcb_dbuf_hi
		.export _ns_get_dcb_dbyt_lo
		.export _ns_get_dcb_dbyt_hi
		.export _ns_get_dcb_aux1
		.export _ns_get_dcb_aux2
		.export _ns_get_dcb_timlo

NS_BASE = $2800

_ns_begin:
		jsr		NS_BASE+0
		rts

_ns_end:
		jsr		NS_BASE+3
		rts

_ns_get_version:
		jsr		NS_BASE+6
		ldx		#0
		rts

_ns_get_base:
		jsr		NS_BASE+9
		rts

; Input: A = byte, Output: A=0 ok, A=1 full
_ns_send_byte:
		jsr		NS_BASE+12
		bcc		ok_send
		lda		#1
		rts
ok_send:
		lda		#0
		rts

; Output: A/X = byte (0-255), or $FFFF if empty
_ns_recv_byte:
		jsr		NS_BASE+15
		bcc		ok_recv
		lda		#$ff
		ldx		#$ff
		rts
ok_recv:
		ldx		#0
		rts

_ns_bytes_avail:
		jsr		NS_BASE+18
		rts

_ns_get_status:
		jsr		NS_BASE+21
		ldx		#0
		rts

_ns_get_video_std:
		jsr		NS_BASE+24
		ldx		#0
		rts

_ns_get_vcount_max:
		jsr		NS_BASE+27
		ldx		#0
		rts

_ns_init_netstream:
		jmp		NS_BASE+30

_ns_get_final_flags:
		jsr		NS_BASE+33
		ldx		#0
		rts

_ns_get_final_audf3:
		jsr		NS_BASE+36
		ldx		#0
		rts

_ns_get_final_audf4:
		jsr		NS_BASE+39
		ldx		#0
		rts

_ns_get_nominal_baud_lo:
		jsr		NS_BASE+42
		ldx		#0
		rts

_ns_get_nominal_baud_hi:
		jsr		NS_BASE+45
		ldx		#0
		rts

_ns_get_debug_b0:
		jsr		NS_BASE+48
		ldx		#0
		rts

_ns_get_debug_b1:
		jsr		NS_BASE+51
		ldx		#0
		rts

_ns_get_debug_b2:
		jsr		NS_BASE+54
		ldx		#0
		rts

_ns_get_debug_b3:
		jsr		NS_BASE+57
		ldx		#0
		rts

_ns_get_debug_b4:
		jsr		NS_BASE+60
		ldx		#0
		rts

_ns_get_debug_b5:
		jsr		NS_BASE+63
		ldx		#0
		rts

_ns_get_sio_status:
		jsr		NS_BASE+66
		ldx		#0
		rts

_ns_get_dcb_dev:
		jsr		NS_BASE+69
		ldx		#0
		rts

_ns_get_dcb_cmd:
		jsr		NS_BASE+72
		ldx		#0
		rts

_ns_get_dcb_stat:
		jsr		NS_BASE+75
		ldx		#0
		rts

_ns_get_dcb_dbuf_lo:
		jsr		NS_BASE+78
		ldx		#0
		rts

_ns_get_dcb_dbuf_hi:
		jsr		NS_BASE+81
		ldx		#0
		rts

_ns_get_dcb_dbyt_lo:
		jsr		NS_BASE+84
		ldx		#0
		rts

_ns_get_dcb_dbyt_hi:
		jsr		NS_BASE+87
		ldx		#0
		rts

_ns_get_dcb_aux1:
		jsr		NS_BASE+90
		ldx		#0
		rts

_ns_get_dcb_aux2:
		jsr		NS_BASE+93
		ldx		#0
		rts

_ns_get_dcb_timlo:
		jsr		NS_BASE+96
		ldx		#0
		rts
