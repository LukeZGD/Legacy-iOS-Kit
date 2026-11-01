#  ibex - main makefile
#
#  Copyright (c) 2010, 2014-2015 xerub
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


.PHONY: all clean distclean

GNUARM_PREFIX ?= /opt/gnuarm/bin/arm-none-eabi-
#PIE = 1

CC = $(GNUARM_PREFIX)gcc
CFLAGS = -Wall -W -pedantic
CFLAGS += -Wno-long-long -Wno-format -Wno-variadic-macros
CFLAGS += -O3 -DDEBUG
#CFLAGS += -mthumb -march=armv7
CFLAGS += -fcall-used-r9

LD = $(GNUARM_PREFIX)gcc
LDFLAGS = -L. -nostdlib
LDFLAGS += -Tscript.ld
LDFLAGS += -Wl,--allow-multiple-definition
LDLIBS = -lp -lgcc

AR = $(GNUARM_PREFIX)ar
ARFLAGS = crus

OBJCOPY = $(GNUARM_PREFIX)objcopy

ifeq ($(TARGET),)
CFLAGS += -fpie
else
include $(TARGET)/target.mak
endif
CFLAGS += -I.
#LDLIBS += -lgcc

SOURCES = \
	main.c

LIBSOURCES = \
	lib/aeabi.c \
	lib/putc.c \
	lib/printf.c \
	lib/strlen.c \
	lib/atoi.c \
	lib/memmem.c \
	lib/memcpy.c \
	lib/memcmp.c \
	lib/memset.c \
	lib/strcmp.c \
	drivers/drivers.c \
	drivers/display/display.c \
	kernel.c \
	patchfinder.c

OBJECTS = $(SOURCES:.c=.o) cache.o
LIBOBJECTS = $(LIBSOURCES:.c=.o)

.S.o:
	$(CC) -o $@ $(CFLAGS) -c $<

.c.o:
	$(CC) -o $@ $(CFLAGS) -c $<

all: payload

payload: payload.elf
	$(OBJCOPY) -O binary $< $@

payload.elf: $(OBJECTS) | entry.o libp.a
	$(LD) -o $@ $(LDFLAGS) $^ $(LDLIBS)

libp.a: $(LIBOBJECTS)
	$(AR) $(ARFLAGS) $@ $^

clean:
	-$(RM) *.o *.elf *.a $(LIBOBJECTS)

distclean: clean
	-$(RM) payload

-include depend
