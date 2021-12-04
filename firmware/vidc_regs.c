/* ArcDVI: Acorn VIDC register accessors
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
#include "uart.h"
#include "vidc_regs.h"
#include "hw.h"


static const char *modes[] = {
        "Normal", "TM0", "TM1", "TM2"
};

#define REG(x, r)       ((x)[(r)/4])

uint32_t        vidc_reg(unsigned int r)
{
        volatile uint32_t *regs = (volatile uint32_t *)IO_BASE_ADDR;

        if (r < 0x100) {
                return REG(regs, r);
        } else {
                return 0;
        }
}

/* Pretty-print the VIDC regs */
void            vidc_dumpregs(void)
{
        volatile uint32_t *regs = (volatile uint32_t *)IO_BASE_ADDR;

        /* Palette */
        mprintf("Palette:\t\t");
        for (int i = 0; i < 16*4; i += 4) {
                mprintf("%03x ", REG(regs, VIDC_PAL_0 + i));
        }
        mprintf("\r\n");

        /* Border */
        mprintf("Border:\t\t\tColour %03x, Hs %3x, He %3x, Vs %3x, Ve %3x\r\n",
                REG(regs, VIDC_BORDERCOL),
                (REG(regs, VIDC_H_BORDER_START) >> 14) & 0x3ff,
                (REG(regs, VIDC_H_BORDER_END) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_BORDER_START) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_BORDER_END) >> 14) & 0x3ff
                );

        /* Cursor */
        mprintf("Pointer:\t\tColours %03x/%03x/%03x, Hs %3x (ext %1x), Vs %3x, Ve %3x\r\n",
                REG(regs, VIDC_CURSORPAL1),
                REG(regs, VIDC_CURSORPAL2),
                REG(regs, VIDC_CURSORPAL3),
                (REG(regs, VIDC_H_CURSOR_START) >> 13) & 0x7ff,
                (REG(regs, VIDC_H_CURSOR_START) >> 11) & 0x3,
                (REG(regs, VIDC_V_CURSOR_START) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_CURSOR_END) >> 14) & 0x3ff
                );

        /* Display */
        mprintf("Display Horizontal:\tCycle %3x, Sync %3x, Dst %3x, Dend %3x, Ilace %3x\r\n",
                (REG(regs, VIDC_H_CYC) >> 14) & 0x3ff,
                (REG(regs, VIDC_H_SYNC) >> 14) & 0x3ff,
                (REG(regs, VIDC_H_DISP_START) >> 14) & 0x3ff,
                (REG(regs, VIDC_H_DISP_END) >> 14) & 0x3ff,
                (REG(regs, VIDC_H_INTERLACE) >> 14) & 0x3ff
                );

        mprintf("Display Vertical:\tCycle %3x, Sync %3x, Dst %3x, Dend %3x\r\n",
                (REG(regs, VIDC_V_CYC) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_SYNC) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_DISP_START) >> 14) & 0x3ff,
                (REG(regs, VIDC_V_DISP_END) >> 14) & 0x3ff
                );

        uint32_t ctrl = REG(regs, VIDC_CONTROL);
        mprintf("Display control:\t%s%s, %sSync, Interlace %s, DMARq %1x, BPP %d, PixClk %d\r\n",
                modes[(ctrl >> 14) & 3],
                (ctrl & 0x100) ? ", TM3" : "",
                (ctrl & 0x80) ? "Composite" : "V",
                (ctrl & 0x40) ? "On" : "Off",
                (ctrl >> 4) & 3,
                1 << ((ctrl >> 2) & 3),
                ctrl & 3);

        /* Sound */
        mprintf("Sound:\t\t\tFreq %2x, stereo %1x %1x %1x %1x %1x %1x %1x\r\n",
                REG(regs, VIDC_SOUND_FREQ) & 0xff,
                REG(regs, VIDC_STEREO0) & 0xf,
                REG(regs, VIDC_STEREO1) & 0xf,
                REG(regs, VIDC_STEREO2) & 0xf,
                REG(regs, VIDC_STEREO3) & 0xf,
                REG(regs, VIDC_STEREO4) & 0xf,
                REG(regs, VIDC_STEREO5) & 0xf,
                REG(regs, VIDC_STEREO6) & 0xf,
                REG(regs, VIDC_STEREO7) & 0xf);

        /* Counters: */
        mprintf("Video DMAs/frame:\t%4x\t\tCursor DMAs/frame:\t%4x\r\n",
                REG(regs, V_DMAC_VIDEO),
                REG(regs, V_DMAC_CURSOR));

        /* Custom/special regs: */
        mprintf("Special:\t\t%08x d %08x\r\n",
                REG(regs, VIDC_SPECIAL), REG(regs, VIDC_SPECIAL_DATA));
}
