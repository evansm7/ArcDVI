/* Toy implementations of some tiny libc functions.
 * We're going for basics and functionality, not perf.
 *
 * 28 Mar 2005
 *
 * Copyright 2005, 2021 Matt Evans
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Software,
 * and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <stdint.h>
#include <stdarg.h>

inline char tolower(char c)
{
	return c | 0x20;
}

// ascii to hex
// success = 0 if couldn't parse input (e.g. EOL, or not hex)
int atoh(char *c, char **end, int *success)
{
	int r = 0;
	int ok = 0;
	char digit = *c;
	char lowerd = tolower(digit);

	while (digit != 0 && ((digit >= '0' && digit <= '9') || (lowerd >= 'a' && lowerd <= 'f'))) {
		int v;
		r = r << 4;
		v = (lowerd >= 'a') ? (lowerd - 'a' + 10) : (lowerd - '0');
		r |= v;
		c++;
		digit = *c;
		lowerd = tolower(digit);
		ok = 1;
	}
	if (ok) {
		*end = c;
	}
	*success = ok;
	return r;
}

int strcmp(char *a, char *b)
{
	int end = 0;
	do {
		if (*a != *b) {
			return 1;
		}
		if (*a == 0) {
			end = 1;
		}
	}
	while (!end);
	return 0;
}

int strncmp(char *a, char *b, int len)
{
	for (; len > 0; len--) {
		if ((*a != *b) || (*a == '\0') || (*b == '\0')) {
			return 1;
		}
		a++;
		b++;
	}
	return 0;
}

int strlen(char *s)
{
	int len = 0;
	while (*s++) { len++; }
	return len;
}

void strcpy(char *dest, char *from)
{
	while (*from) {
		*dest++ = *from++;
	}
}

// The least optimal memcpy in the world:
void memcpy(void *dest, void *from, int num)
{
	uint8_t *d = dest;
	uint8_t *s = from;
	for (; num > 0; num--) {
		*d++ = *s++;
	}
}

void memset(void *dest, int val, int len)
{
	uint8_t *d = dest;
	while (len-- > 0) {
		*d++ = (uint8_t)val;
	}
}

static void 	pdec(void (*putch)(char, void*), void *putarg,
		     unsigned long int n, int unsgnd)
{
	char buff[21]; /* 2^64 is 20 digits */
	char *p = buff;

	/* Write to buffer from lowest digit first, then read out in reverse */
	if (!unsgnd) {
		long ns = n;
		if (ns < 0) {
			putch('-', putarg);
			n = -ns;
		}
	}

	do {
		*p++ = '0' + (n % 10);
	} while ((n /= 10) != 0);

	while (p > buff)
	{
		putch(*--p, putarg);
	}
}

static void phex(void (*putch)(char, void*), void *putarg,
		 unsigned long int n, int digits, int caps, char pad)
{
	int i;
	char b = caps ? 'A' : 'a';
        int clz = 1;
	for (i = digits-1; i >= 0; i--) {
		int d = (n >> (i*4)) & 0xf;
		if ((d != 0) || (i == 0) || !clz) {
                        clz = 0;
			if (d > 9)
				putch(b + d - 10, putarg);
			else
				putch('0' + d, putarg);
		} else {
			if (pad != 0)
				putch(pad, putarg);
		}
	}
}

/* Simple dumb printf-style scanner. */
void do_printf_scan(void (*putch)(char, void*), void *putarg,
		    const char *fmt, va_list args)
{
	char *cp;
	char c;

	while ((c = *fmt++) != '\0') {
		int saw_long = 0;
		int saw_unsigned = 0;
		int saw_zeropad = 0;
		int saw_spacepad = 0;
		int pr_digits = 0;

		if (c != '%') {
			putch(c, putarg);
			continue;
		}
		/* Else ... Hit a %, what's the next char? */
	parse_perc:
		if ((c = *fmt++) != '\0') {
			switch (c) {
			case '%':
				putch('%', putarg);
				break;
			case 'l':
				saw_long = 1;
				goto parse_perc;
				break;
			case 'u':
				saw_unsigned = 1;
				goto parse_perc;
				break;
			case 's':
				cp = va_arg(args, char *);
				while ((c = (*cp++)) != 0) {
					putch(c, putarg);
				}
				break;
			case 'p':
				putch('0', putarg);
				putch('x', putarg);
				saw_long = 1;
			case 'x':
			case 'X':
			{
				char p = 0;
				if (saw_spacepad && pr_digits != 0)
					p = ' ';
				else if (saw_zeropad)
					p = '0';

				if (saw_long)
					phex(putch, putarg, va_arg(args, long),
					     (pr_digits == 0) ? 16 : pr_digits, (c == 'X'), p);
				else
					phex(putch, putarg, va_arg(args, int),
					     (pr_digits == 0) ? 8 : pr_digits, (c == 'X'), p);
			}
			break;
			case 'c':
				putch(va_arg(args, int), putarg);
				break;
				/* Numbers -- zero sets zeropad, others set digits */
			case '0':
				if (!saw_zeropad) {
					saw_zeropad = 1;
					goto parse_perc;
				} /* Else fall through */
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
			case '8':
			case '9':
				pr_digits = (pr_digits * 10) + (c - '0');
				goto parse_perc;
			case ' ':
				saw_spacepad = 1;
				goto parse_perc;
				break;
			case 'd':
				if (saw_long)
					pdec(putch, putarg, va_arg(args, long), saw_unsigned);
				else
					pdec(putch, putarg, va_arg(args, int), saw_unsigned);
				break;
				/* Things unsupported just yet... */
			case 'o':
				putch('[', putarg);
				phex(putch, putarg, va_arg(args, int), 8, 0, 0);
				putch(']', putarg);
				break;
			default:
				putch(c, putarg);
			}
		}
	}
}
