/*
 *  ibex - payload linker script: create payload entrypoint (see trampoline)
 *
 *  Copyright (c) 2010, 2015 xerub
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


OUTPUT_FORMAT("elf32-littlearm")
OUTPUT_ARCH(arm)
STARTUP(entry.o)
ENTRY(_start)
SECTIONS {
    .text : {
        *(.text)
    }

    _etext = .;
    PROVIDE (etext = .);

    .rodata : {
        *(.rodata)
    }

    .data : {
        *(.data)
    }

    .got : {
        *(.got.plt) *(.got)
    }

    _edata = .;
    PROVIDE (edata = .);

    __bss_start = .;
    __bss_start__ = .;

    .bss : {
        *(.bss)
        . = ALIGN(4);
    }
    . = ALIGN(4);

    _bss_end__ = . ; __bss_end__ = . ; __end__ = . ;

    _end = .;
    PROVIDE (end = .);
}
