/* Deal with picosoc's simpleuart, supply mprintf
 *
 * Copyright 2017, 2021 Matt Evans
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

#define _XOPEN_SOURCE 601

#include <stdarg.h>
#include <stddef.h>
#include <inttypes.h>

#include "libcfns.h"
#include "uart.h"


#ifdef SIM
static  int cfd;
#endif

void    uart_init(void)
{
#ifdef SIM
        cfd = posix_openpt(O_RDWR | O_NOCTTY);
        if (cfd < 0) {
                perror("openpt: ");
                exit(1);
        }
        if (grantpt(cfd) < 0) {
                perror("grantpt: ");
                exit(1);
        }
        if (unlockpt(cfd) < 0) {
                perror("unlockpt: ");
                exit(1);
        }
        char *slave = ptsname(cfd);
        printf(" [ Slave tty is %s ]\n"
               "    screen %s 9600\n", slave, slave);
        /* Wait for connection/hit enter */
        while (!uart_ch_rdy()) {
                usleep(100000);
        }
        uart_getch();
#endif
}

void	uart_putch(char c)
{
#ifdef SIM
        int r = write(cfd, &c, 1);
        if (r < 0) {
                perror("write: ");
                exit(1);
        }
#else
        *((volatile uint32_t*)UART_ADDR) = c;
#endif
}

char 	uart_getch(void)
{
#ifdef SIM
        char c;
        int r = read(cfd, &c, 1);
        if (r < 0) {
                perror("read: ");
                exit(1);
        }
        return c;
#else
        uint32_t d = 0;
        do {
                d = *((volatile uint32_t*)UART_ADDR);
        } while (d == ~0);
	return d & 0xff;
#endif
}

char 	uart_testgetch(int *ready)
{
#ifdef SIM
        struct pollfd pfd = { .fd = cfd,
                              .events = POLLIN,
                              .revents = 0 };
        int r = poll(&pfd, 1, 0);
        if (r > 0) {
                char c;
                r = read(cfd, &c, 1);
                if (r < 0) {
                        perror("read: ");
                        exit(1);
                }
                *ready = 1;
                return c;
        } else if (r == 0) {
                *ready = 0;
                return 0;
        } else {
                perror("poll: ");
                exit(1);
        }
#else
        uint32_t d = *((volatile uint32_t*)UART_ADDR);

        *ready = !!(d != ~0);
	return d & 0xff;
#endif
}

static void u0_putch(char c, void *arg)
{
	/* Write to UART */
	uart_putch(c);
}

void 	mprintf(const char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);
	do_printf_scan(u0_putch, NULL, fmt, args);
	va_end(args);
}
