@  ibex - cache functions
@
@  Copyright (c) 2015 xerub
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


	.global	flush_icache
	.arm
	.type	flush_icache, %function
flush_icache:
	mov	r0, #0
	mcr	p15, 0, r2, c7, c5, 0
	.long	0xF57FF04F				@ dsb	sy
	.long	0xF57FF06F				@ isb	sy
	bx	lr
	.size	flush_icache, .-flush_icache

