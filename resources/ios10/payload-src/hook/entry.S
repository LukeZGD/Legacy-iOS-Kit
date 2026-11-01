@  ibex - payload trampoline: create payload entrypoint (see linker script)
@
@  Copyright (c) 2010, 2015 xerub
@
@ This program is free software; you can redistribute it and/or modify
@ it under the terms of the GNU General Public License as published by
@ the Free Software Foundation; either version 2 of the License, or
@ (at your option) any later version.
@
@ This program is distributed in the hope that it will be useful,
@ but WITHOUT ANY WARRANTY; without even the implied warranty of
@ MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
@ GNU General Public License for more details.
@
@ You should have received a copy of the GNU General Public License
@ along with this program.  If not, see <http://www.gnu.org/licenses/>.


	.global	_start
	.arm
	.type	_start, %function
_start:
#ifdef __pie__
	nop

	ldr	r8, =(_GLOBAL_OFFSET_TABLE_ + 0)
	add	r8, pc, r8
	add	r8, #(.Lsize - . - 4)			@ .Lsize - (pcrel insn addr + 8)

#ifdef ANY_BASE
	@ we were linked at non-zero base
	ldr	r9, .Laddr
	sub	r9, pc
	add	r9, #(. + 4 - _start)			@ pcrel insn addr + 8
#endif

	@ fixup GOT
	ldr	r3, .Ledata
0:
	subs	r3, r3, #4
	ldrge	r12, [r8, r3]
#ifdef ANY_BASE
	subge	r12, r9
#else
	addge	r12, r12, pc
	subge	r12, #(. + 4)				@ pcrel insn addr + 8 // assume zero base
#endif
	strge	r12, [r8, r3]
	bge	0b

	@ fixup main trampoline
	ldr	r12, .Lmain
	add	r12, r8
	str	r12, .Lmain

	@ short-circuit next run
	mov	r12, #0xEA000000
	add	r12, #((.Lsave - _start - 8) / 4)	@ b	.Lsave
	str	r12, _start

	@ clear BSS
	ldr	r3, .Lend
	add	r3, r8
	ldr	r12, .Ledata
	add	r8, r12, r8
	mov	r12, #0
1:
	sub	r3, r3, #4
	cmp	r3, r8
	strge	r12, [r3]
	bge	1b

	@ clear icache
	mcr	p15, 0, r12, c7, c5, 0
	.long	0xF57FF04F				@ dsb	sy
	.long	0xF57FF06F				@ isb	sy

	@ save registers
.Lsave:
	adr	r3, .Lregs
	stmia	r3, {r4-r8,r10,r11,sp,lr}
.Ljump:
	.long	0xe59ff000 + (.Lmain - . - 8)		@ ldr	pc, =.Lmain

.Lend:	.long	end(GOTOFF)
.Ledata:.long	edata(GOTOFF)
.Lmain:	.long	_main(GOTOFF)
#ifdef ANY_BASE
.Laddr:	.long	_start
#endif

#else  /* !__pie__ */

	@ clear BSS (once)
	ldr	r3, .Lend
	cmp	r3, #0
	beq	0f
	ldr	r8, .Ledata
	mov	r12, #0
1:
	sub	r3, r3, #4
	cmp	r3, r8
	strge	r12, [r3]
	bge	1b
	str	r12, .Lend
0:
	adr	r3, .Lregs
	stmia	r3, {r4-r8,r10,r11,sp,lr}
	ldr	pc, =_main				@ b _main is shorter but cannot swith to Thumb

.Lend:	.long	end
.Ledata:.long	edata
#endif /* !__pie__ */

.Lregs:	.long	0, 0, 0, 0, 0, 0, 0, 0, 0

	.global	_exit
	.type	_exit, %function
_exit:
	adr	r1, .Lregs
	ldmia	r1, {r4-r8,r10,r11,sp,pc}
	.size	_exit, .-_exit
.Lsize:
	.size	_start, .-_start
