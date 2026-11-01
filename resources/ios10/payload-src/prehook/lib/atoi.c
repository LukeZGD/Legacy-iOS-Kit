/*
 *  ibex - pseudo-library
 *
 *  Copyright (c) 2015 xerub
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




int
atoi(const char *nptr)
{
    int val = 0;
    int neg = 0;
    if (*nptr == '-') {
        neg = 1;
        nptr++;
    }
    for (;;) {
        int ch = *nptr++;
        if (ch < '0' || ch > '9') {
            break;
        }
        val = (val << 3) + (val << 1) + (ch - '0');
    }
    return neg ? -val : val;
}
