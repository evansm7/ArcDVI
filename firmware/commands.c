/* Simple command handler:
 * Provides a trivial CLI, with command handlers/parameters etc.
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

#include <ctype.h>
#include "commands.h"
#include "uart.h"
#include "vidc_regs.h"
#include "video.h"
#include "libcfns.h"


typedef void (*cmd_fn_t)(char *args);

typedef struct {
        const char *format;
        const char *help;
        cmd_fn_t handler;
} cmd_t;


void	cmd_init(void)
{
}

/*****************************************************************************/
/* Utilities */

static char *skipwhitespace(char *str)
{
        while ((*str != '\0') && ((*str == ' ') || (*str == '\t'))) { str++; }
        return str;
}

static int get_addr_len(char **args, unsigned int *addr, unsigned int *len)
{
        int OKa;

        *addr = atoh(*args, args, &OKa);
        if (!OKa)
        {
                mprintf("\r\n Syntax error, address expected\r\n");
                return 0;
        }
        *args = skipwhitespace(*args);
        *len = atoh(*args, args, &OKa);
        if (!OKa)
        {
                mprintf("\r\n Syntax error, len expected\r\n");
                return 0;
        }
        return 1;
}

static void pr_hexdump(unsigned int *from, int words, unsigned int praddr)
{
        int n = 0;
        unsigned int *linestart = 0;
        const int wordsPerLine = 4;

        for (; words > 0; words--) {
                if ((n & (wordsPerLine-1)) == 0) {
                        mprintf("  %08x: ", praddr);
                        linestart = from;
                }
                uint32_t word = ~0;
                word = *from;
                mprintf("%08x ", word);
                from++;
                praddr += 4;

                if ((n & (wordsPerLine-1)) == (wordsPerLine-1)) {
                        int i;
                        // End of the line; print ascii
                        for (i = 0; i < (wordsPerLine * 4); i++) {
                                unsigned char c;
                                c = ((unsigned char *)linestart)[i];
                                if (c < ' ' || c > 127) {
                                        c = '.';
                                }
                                uart_putch(c);
                        }
                        mprintf("\r\n");
                }
                n++;
        }
        if ((n & (wordsPerLine-1)) != 0) {
                mprintf("\r\n");
        }
}


/*****************************************************************************/
/* Commands */
static void cmd_read(char *args, int size)
{
        int OKa;
        unsigned int addr;

        addr = atoh(args, &args, &OKa);
        if (!OKa) {
                mprintf("\r\n Syntax error, arg 1\r\n");
        } else {
                if (size == 1) {
                        uint8_t db = ~0;
                        db = *(uint8_t *)addr;
                        mprintf("\r\n  %08x\t= %02x\r\n", addr, db);
                } else {
                        uint32_t db = ~0;
                        /* Addrs must be aligned, says me: */
                        addr &= ~3;
                        db = *(uint32_t *)addr;
                        mprintf("\r\n  %08x\t= %08x\r\n", addr, db);
                }
        }
}

static void cmd_rb(char *args)
{
        cmd_read(args, 1);
}

static void cmd_rw(char *args)
{
        cmd_read(args, 4);
}

static void cmd_write(char *args, int size)
{
        int OK;
        unsigned int addr, data;

        addr = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 1\r\n");
        } else {
                args = skipwhitespace(args);
                data = atoh(args, &args, &OK);
                if (!OK) {
                        mprintf("\r\n Syntax error, arg 2\r\n");
                        return;
                }

                if (size == 1) {
                        *(uint8_t *)addr = data;
                        mprintf("\r\n  [%08x]\t<= %02x\r\n", addr, data);
                } else {
                        *(uint32_t *)addr = data;
                        mprintf("\r\n  [%08x]\t<= %08x\r\n", addr, data);
                }
        }
}

static void cmd_wb(char *args)
{
        cmd_write(args, 1);
}

static void cmd_ww(char *args)
{
        cmd_write(args, 4);
}

static void cmd_vtx(char *args)
{
        int OK;
        unsigned int xres, fp, width, bp, wpl;

        xres = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 0\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        fp = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 1\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        width = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 2\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        bp = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 3\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        wpl = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 4\r\n");
                goto fail;
        }

        // Write video regs:
        video_set_x_timing(xres, fp, width, bp, wpl);
fail:
}

static void cmd_vty(char *args)
{
        int OK;
        unsigned int yres, fp, width, bp;

        yres = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 0\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        fp = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 1\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        width = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 2\r\n");
                goto fail;
        }
        args = skipwhitespace(args);
        bp = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 3\r\n");
                goto fail;
        }

        // Write video regs
fail:
        video_set_y_timing(yres, fp, width, bp);
}

static void cmd_setmode(char *args)
{
        int OK;
        unsigned int mode;

        mode = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error in arg\r\n");
                return;
        }

        video_setmode(mode);
}

static void cmd_vt(char *args)
{
        video_dump_timing_regs();
}

static void cmd_cursorctrl(char *args)
{
        int OK;
        unsigned int xo;

        xo = atoh(args, &args, &OK);
        if (!OK) {
                mprintf("\r\n Syntax error, arg 0\r\n");
                goto fail;
        }
        video_set_cursor_x(xo);
fail:
}

static void cmd_sync(char *args)
{
        video_sync();
}

static void cmd_vidc_dump(char *args)
{
        vidc_dumpregs();
}

static void cmd_dump(char *args)
{
        unsigned int addr;
        unsigned int len;

        if (!get_addr_len(&args, &addr, &len)) {
                return;
        }
        mprintf("\r\n");
        pr_hexdump((unsigned int *)(uintptr_t)addr, len >> 2, (unsigned int)addr);
}

extern uint8_t flag_autoprobe_mode;
static void cmd_autoprobe(char *args)
{
        flag_autoprobe_mode = !flag_autoprobe_mode;
        mprintf("Autoprobe is %s\r\n", flag_autoprobe_mode ? "on" : "off");
}


/*****************************************************************************/

static void cmd_help(char *args);

static cmd_t commands[] = {
        { .format = "help",
          .help = "help\t\t\tGives this help",
          .handler = cmd_help },
        { .format = "rb",
          .help = "r{b,w} <addr>\t\tReads byte/word at addr",
          .handler = cmd_rb },
        { .format = "rw",
          .help = 0,
          .handler = cmd_rw },
        { .format = "wb",
          .help = "w{b,w} <addr> <data>\tWrites given byte/word to addr",
          .handler = cmd_wb },
        { .format = "ww",
          .help = 0,
          .handler = cmd_ww },
        { .format = "vtx",
          .help = "vtx <xpix> <fp> <sync width> <bp> <dma wpl-1>\tSet X video timing",
          .handler = cmd_vtx },
        { .format = "vty",
          .help = "vty <ypix> <fp> <sync width> <bp>\t\tSet Y video timing",
          .handler = cmd_vty },
          // FIXME: And set res
        { .format = "vt",
          .help = "vt\t\t\tDump video timing",
          .handler = cmd_vt },
        { .format = "v",
          .help = "v\t\t\tDump VIDC regs",
          .handler = cmd_vidc_dump },
        { .format = "m",
          .help = "m <mode>\t\tSet mode (arc number)",
          .handler = cmd_setmode },
        { .format = "cc",
          .help = "cc <cursor x offset>\t\t\tSet cursor x offset",
          .handler = cmd_cursorctrl },
        { .format = "sync",
          .help = "sync\t\t\tResync display to VIDC",
          .handler = cmd_sync },
        { .format = "a",
          .help = "a\t\t\tToggle mode autoprobing",
          .handler = cmd_autoprobe },
        { .format = "dm",
          .help = "dm <addr> <len>\t\tHexdump memory",
          .handler = cmd_dump },
};

static int num_commands = sizeof(commands)/sizeof(cmd_t);

/* Special command */
static void cmd_help(char *args)
{
        mprintf("\r\n Help:\r\n");
        for (int i = 0; i < num_commands; i++) {
                if (commands[i].help)
                        mprintf("\t%s\r\n", commands[i].help);
        }
}

void cmd_parse(char *linebuffer, int len)
{
        char *cmd_start;
        int ran_cmd = 0;

        cmd_start = skipwhitespace(linebuffer);

        /* Check for blank line: */
        if (cmd_start - linebuffer == len) {
                return;
        }

        for (int i = 0; i < num_commands; i++) {
                int clen = strlen((char *)commands[i].format);
                if (strncmp(cmd_start, (char *)commands[i].format, clen) == 0) {
                        commands[i].handler(skipwhitespace(cmd_start + clen));
                        ran_cmd = 1;
                        break;
                }
        }
        if (!ran_cmd) {
                mprintf(" -- Unknown command!\r\n");
                cmd_help(cmd_start);
        }
}
