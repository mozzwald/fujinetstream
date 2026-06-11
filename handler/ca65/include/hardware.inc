;	Altirra - Atari 800/800XL/5200 emulator
;	Modular Kernel ROM - Hardware register definitions
;	Copyright (C) 2008-2016 Avery Lee
;
;	Copying and distribution of this file, with or without modification,
;	are permitted in any medium without royalty provided the copyright
;	notice and this notice are preserved.  This file is offered as-is,
;	without any warranty.
;
;  Converted from MADS to CA65 syntax.

.ifndef f_HARDWARE_INC
f_HARDWARE_INC = 1

;==========================================================================
; GTIA
;
m0pf	=	$d000
m1pf	=	$d001
m2pf	=	$d002
m3pf	=	$d003
p0pf	=	$d004
p1pf	=	$d005
p2pf	=	$d006
p3pf	=	$d007
m0pl	=	$d008
m1pl	=	$d009
m2pl	=	$d00a
m3pl	=	$d00b
p0pl	=	$d00c
p1pl	=	$d00d
p2pl	=	$d00e
p3pl	=	$d00f

hposp0	=	$d000
hposp1	=	$d001
hposp2	=	$d002
hposp3	=	$d003
hposm0	=	$d004
hposm1	=	$d005
hposm2	=	$d006
hposm3	=	$d007
sizep0	=	$d008
sizep1	=	$d009
sizep2	=	$d00a
sizep3	=	$d00b
sizem	=	$d00c
grafp0	=	$d00d
grafp1	=	$d00e
grafp2	=	$d00f
grafp3	=	$d010
grafm	=	$d011
trig0	=	$d010
trig1	=	$d011
trig2	=	$d012
colpm0	=	$d012
trig3	=	$d013
colpm1	=	$d013
pal	=	$d014
colpm2	=	$d014
colpm3	=	$d015
colpf0	=	$d016
colpf1	=	$d017
colpf2	=	$d018
colpf3	=	$d019
colbk	=	$d01a
prior	=	$d01b
vdelay	=	$d01c
gractl	=	$d01d
hitclr	=	$d01e
consol	=	$d01f

;==========================================================================
; POKEY
;
pot0	=	$d200
audf1	=	$d200
pot1	=	$d201
audc1	=	$d201
pot2	=	$d202
audf2	=	$d202
pot3	=	$d203
audc2	=	$d203
pot4	=	$d204
audf3	=	$d204
pot5	=	$d205
audc3	=	$d205
pot6	=	$d206
audf4	=	$d206
pot7	=	$d207
audc4	=	$d207
audctl	=	$d208
kbcode	=	$d209
skres	=	$d20a
potgo	=	$d20b
serin	=	$d20d
serout	=	$d20d
irqen	=	$d20e
irqst	=	$d20e
skctl	=	$d20f
skstat	=	$d20f

;==========================================================================
; PIA
;
porta	=	$d300
portb	=	$d301
pactl	=	$d302
pbctl	=	$d303

;==========================================================================
; ANTIC
;
dmactl	=	$d400
chactl	=	$d401
dlistl	=	$d402
dlisth	=	$d403
hscrol	=	$d404
vscrol	=	$d405
pmbase	=	$d407
chbase	=	$d409
wsync	=	$d40a
vcount	=	$d40b
penh	=	$d40c
penv	=	$d40d
nmien	=	$d40e
nmist	=	$d40f
nmires	=	$d40f

;==========================================================================
; 6502
;
nmivec	=	$fffa
resvec	=	$fffc
irqvec	=	$fffe

.endif
