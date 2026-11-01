/*
 * Copyright (c) 2000 Apple Computer, Inc. All rights reserved.
 *
 * @APPLE_LICENSE_HEADER_START@
 * 
 * The contents of this file constitute Original Code as defined in and
 * are subject to the Apple Public Source License Version 1.1 (the
 * "License").  You may not use this file except in compliance with the
 * License.  Please obtain a copy of the License at
 * http://www.apple.com/publicsource and read it before using this file.
 * 
 * This Original Code and all software distributed under the License are
 * distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE OR NON-INFRINGEMENT.  Please see the
 * License for the specific language governing rights and limitations
 * under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */
/*
 *  mem.c - Standard memory functions.
 *
 *  Copyright (c) 1998-2002 Apple Computer, Inc.
 *
 *  DRI: Josh de Cesare
 */
#include <stddef.h>

void *memset(void *dst, int ch, size_t len)
{
  long tmp = 0x01010101 * (ch & 0x000000FF);
  char *dest = dst;

  if (len < 32) while (len--) *dest++ = ch;
  else {
    /* do the front chunk as chars */
    while ((long)dest & 3) {
      len--;
      *dest++ = ch;
    }
    
    /* do the middle chunk as longs */
    while (len > 3) {
      len -= 4;
      *(long *)dest = tmp;
      dest += 4;
    }
    
    /* do the last chunk as chars */
    while (len--) *dest++ = ch;
  }

  return dst;
}
