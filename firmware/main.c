/* ArcDVI firmware main loop
 *
 * Copyright 2021 Matt Evans
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

#include "firmware.h"
#include "custom_ops.h"
#include "vidc_regs.h"
#include "uart.h"
#include "commands.h"
#include "video.h"


#define UART_PROMPT "> "

/* Look for new UART activity, basic line editing/dispatch command: */
static void     serial_poll(void)
{
        static char buf[100];
        static unsigned int len = 0;
        static int line_done = 0;

        int r;
        char c = uart_testgetch(&r);

        if (r) {
                switch (c)
                {
                case '\r':
                        //break;    // Nothing, ignore CRLF style newlines.
                case '\n':
                        // end of line!
                        uart_putch('\r');
                        uart_putch('\n');
                        buf[len] = '\0';
                        line_done = 1;
                        break;
                case 8:
                        // Delete/backspace
                        if (len > 0)
                        {
                                len--;
                                // Rubout the char:
                                uart_putch(8);
                                uart_putch(' ');
                                uart_putch(8);
                        }
                        break;
                default:
                        if (len < (sizeof(buf)-1))
                        {
                                buf[len] = c;
                                len++;
                                uart_putch(c);  // echo
                        } // else discard char, the line's too long!
                }

                if (line_done) {
                        cmd_parse(buf, len);
                        line_done = 0;
                        len = 0;
                        mprintf(UART_PROMPT);
                }
        }
}

uint8_t flag_autoprobe_mode = 1;

static void     vidc_config_poll(void)
{
        volatile uint32_t *vr = (volatile uint32_t *)VIDO_BASE_ADDR;
        uint32_t s = vr[VIDO_REG_SYNC];

        int status = !!(s & 8);
        int ack = !!(s & 4);

        if (status != ack) {
                // FIXME: Delay a frame or so, so that all writes have Probably Happened
                mprintf("<VIDC RECONFIG %08x>\r\n", s);
                vr[VIDO_REG_SYNC] = s ^ 4; // Flip ack, enables further detection.

                if (flag_autoprobe_mode)
                        video_probe_mode();
        }
}

void    main(void)
{
	mprintf("Good morning, world\n");

        cmd_init();

        /* Active hot-spinning loop to poll various services (monitor regs,
         * interactive UART IO, update OSD, etc.)
         */
        mprintf(UART_PROMPT);

        while (1) {
                /* Poll UART */
                serial_poll();

                vidc_config_poll();
        }

        mprintf("\nDone\n");
}

