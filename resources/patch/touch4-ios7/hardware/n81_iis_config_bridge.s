/* SPDX-License-Identifier: GPL-3.0-or-later */
.syntax unified
.thumb
.text
.balign 4
.global _n81_iis_config_bridge
.global _hook_resume_normal
.global _hook_resume_result
.global _hook_resume_fail
.global _hook_old_config
.global _hook_new_config
.thumb_func
_n81_iis_config_bridge:
    /* r0=OSData length, r4=IIS device, r6=OSData, original frame intact. */
    movs r5, #0
    cmp r0, #36
    bhs .Lnormal
    cmp r0, #32
    bne .Lfail
    /* Fetch bytes only after proving the exact legacy structure length. */
    ldr r0, [r6]
    ldr r1, [r0, #0x68]
    mov r0, r6
    blx r1
    adr r1, _hook_old_config
    movs r2, #8
.Lcompare:
    ldr r3, [r0], #4
    ldr r12, [r1], #4
    cmp r3, r12
    bne .Lfail
    subs r2, #1
    bne .Lcompare
    /* Translate only the exact N81 legacy codec config, never arbitrary data. */
    ldr r0, [r4]
    ldr r8, [r0, #0x34c]
    adr r1, _hook_new_config
    mov r0, r4
    blx r8
_hook_resume_result:
    .byte 0, 0, 0, 0
.Lnormal:
_hook_resume_normal:
    .byte 0, 0, 0, 0
.Lfail:
_hook_resume_fail:
    .byte 0, 0, 0, 0
.balign 4
_hook_old_config:
    .long 0x180, 0, 0x03100081, 4, 0x1000, 4, 0x28000300, 0
_hook_new_config:
    .long 0x10, 0x00010002, 6000000, 0, 0, 3, 3, 0x10100202, 0
