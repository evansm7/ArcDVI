/*
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

#ifndef VIDC_REGS_H
#define VIDC_REGS_H

#define VIDC_PAL_0              0
#define VIDC_BORDERCOL          0x40
#define VIDC_CURSORPAL1         0x44
#define VIDC_CURSORPAL2         0x48
#define VIDC_CURSORPAL3         0x4c
#define VIDC_SPECIAL            0x50
#define VIDC_SPECIAL_DATA       0x54
#define VIDC_STEREO7            0x60
#define VIDC_STEREO0            0x64
#define VIDC_STEREO1            0x68
#define VIDC_STEREO2            0x6c
#define VIDC_STEREO3            0x70
#define VIDC_STEREO4            0x74
#define VIDC_STEREO5            0x78
#define VIDC_STEREO6            0x7c
#define VIDC_H_CYC              0x80
#define VIDC_H_SYNC             0x84
#define VIDC_H_BORDER_START     0x88
#define VIDC_H_DISP_START       0x8c
#define VIDC_H_DISP_END         0x90
#define VIDC_H_BORDER_END       0x94
#define VIDC_H_CURSOR_START     0x98
#define VIDC_H_INTERLACE        0x9c
#define VIDC_V_CYC              0xa0
#define VIDC_V_SYNC             0xa4
#define VIDC_V_BORDER_START     0xa8
#define VIDC_V_DISP_START       0xac
#define VIDC_V_DISP_END         0xb0
#define VIDC_V_BORDER_END       0xb4
#define VIDC_V_CURSOR_START     0xb8
#define VIDC_V_CURSOR_END       0xbc
#define VIDC_SOUND_FREQ         0xc0
#define VIDC_CONTROL            0xe0

// Counters
#define V_DMAC_VIDEO            0x100
#define V_DMAC_CURSOR           0x104

void            vidc_dumpregs(void);
uint32_t        vidc_reg(unsigned int r);


static inline int vidc_bpp_to_hdsr_offset(int bpp_po2)
{
        switch (bpp_po2) {
        case 0: // 1BPP
                return 19;
        case 1: // 2BPP
                return 11;
        case 2: // 4BPP
                return 7;
        case 3: // 8BPP
                return 5;
        default:
                return 0;
        }
}

#endif
