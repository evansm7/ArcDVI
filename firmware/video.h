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

#ifndef VIDEO_H
#define VIDEO_H

/* Video output register interface: */
#define VIDO_REG_RES_X          0
/* 31           double_x        0 = regular pixels, 1 = display x pixels twice
 * 10:0         x_output_res
 */
#define VIDO_REG_HS_FP          1
/* 10:0         horiz front porch
 */
#define VIDO_REG_HS_WIDTH       2
/* 10:0         horiz sync width
 */
#define VIDO_REG_HS_BP          3
/* 10:0         horiz back porch
 */
#define VIDO_REG_RES_Y          4
/* 31           double_y        0 = regular lines, 1 = display y lines twice
 * 10:0         y_output_res
*/
#define VIDO_REG_VS_FP          5
/* 10:0         vertical front porch
 */
#define VIDO_REG_VS_WIDTH       6
/* 10:0         vertical sync width
 */
#define VIDO_REG_VS_BP          7
/* 10:0         vertical back porch
 */
#define VIDO_REG_SYNC           8
/* 4            Flyback status
 * 3            Display timing register status (toggles when HCR/VCR changed, if [2]==[3]
 * 2            Display timing register status ack
 * 1            Frame synchronisation ack
 * 0            Frame synchronisation request
 */
#define VIDO_REG_WPLM1          9
/* 7:0          Words per line, minus one
 */
#define VIDO_REG_CTRL           10
/* 31           HiRes   (1 = in high res mode)
 * 30:28        log2 of bits per pixel (values 0-4 valid)
 * 10:0         Cursor X offset
 */

void    video_sync(void);
void    video_setmode(int mode);
void    video_probe_mode(void);
void    video_dump_timing_regs(void);
void    video_set_x_timing(unsigned int xres, unsigned int fp, unsigned int sw,
                           unsigned int bp, unsigned int wpl);
void    video_set_y_timing(unsigned int yres, unsigned int fp, unsigned int sw,
                           unsigned int bp);
void    video_set_cursor_x(unsigned int offset);

#endif

