/* ArcDVI: Video timing
 *
 * This component generates video timing/strobes/test card.
 *
 * Timing is dynamically provided (possibly from another clock domain)
 * with an update handshake.  The handshake synchronises the scan-out
 * to an async input flyback signal's falling edge (a bit like a genlock).
 *
 * 17 Nov 2021
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


//`define INCLUDE_HIGH_COLOUR // Not finished!

module video_timing(input wire        	     pclk,
                    output wire [7:0]        o_r,
                    output wire [7:0]        o_g,
                    output wire [7:0]        o_b,
                    output wire              o_hsync,
                    output wire              o_vsync,
                    output wire              o_blank,
                    output wire              o_de,

                    /* Dynamic timing configuration */
                    input wire [10:0]        t_horiz_res,
                    input wire [10:0]        t_horiz_fp,
                    input wire [10:0]        t_horiz_sync_width,
                    input wire [10:0]        t_horiz_bp,
                    input wire [10:0]        t_vert_res,
                    input wire [10:0]        t_vert_fp,
                    input wire [10:0]        t_vert_sync_width,
                    input wire [10:0]        t_vert_bp,
                    input wire [7:0]         t_words_per_line_m1,
                    input wire [2:0]         t_bpp,
                    input wire               t_hires,
                    input wire               t_double_x,
                    input wire               t_double_y,

                    /* Per-frame dynamic stuff, e.g. cursor */
                    input wire [10:0]        v_cursor_x,
                    input wire [9:0]         v_cursor_y,
                    input wire [9:0]         v_cursor_yend,

                    input wire [(16*12)-1:0] vidc_palette,
                    input wire [(3*12)-1:0]  vidc_cursor_palette,

                    input wire               vidc_special_written,
                    input wire [23:0]        vidc_special,
                    input wire [23:0]        vidc_special_data,

                    /* VIDC incoming data written to line buffer */
                    input wire               load_dma_clk,
                    input wire               load_dma,
                    input wire               load_dma_cursor,
                    input wire [31:0]        load_dma_data,

                    /* VIDC external flyback to sync to: */
                    input wire               sync_flyback,

                    /* Sync handshake (when t_* are stable) */
                    input wire               config_sync_req,
                    output reg               config_sync_ack,

                    input wire               enable_test_card
                    );

   parameter ctr_width_x	= 11;
   parameter ctr_width_y	= 11;


   ////////////////////////////////////////////////////////////////////////////////
   // VSync/frame synchronisation

   /* A request toggles, we sync, then toggle ack.
    *
    * The purpose is to wait for the external flyback to finish, then
    * kick off the timing generator to bumble on, synchronised forever more.
    */
   reg [1:0]    pclk_sync_req;
   reg [2:0]    pclk_sync_fb; // Synchroniser and 'last' value
   always @(posedge pclk) begin
           pclk_sync_req 	<= {pclk_sync_req[0], config_sync_req};
           pclk_sync_fb 	<= {pclk_sync_fb[1:0], sync_flyback};
   end

   wire 	my_sync_req          = pclk_sync_req[1];
   wire 	sync_request_pending = my_sync_req != config_sync_ack;
   wire         flyback_falling      = pclk_sync_fb[1] == 0 && pclk_sync_fb[2] == 1;

   reg          doing_resync;
   reg          vid_enable;
   reg [1:0] 	init_ctr;

   initial begin // Bleh, add RESET pls
      config_sync_ack  <= 0;
      doing_resync <= 0;
      vid_enable   <= 1;
   end

   always @(posedge pclk) begin
           if (!doing_resync) begin
                   if (sync_request_pending) begin
                           doing_resync <= 1;
                           vid_enable   <= 0;
                           init_ctr     <= 2'h3;
                   end
           end else if (init_ctr != 0) begin
                   /* Reset for at least 3 cycles. This might miss
                    * a sync point which is OK; we wait for the next frame.
                    */
                   init_ctr               <= init_ctr - 1;
           end else if (flyback_falling) begin
                   // Flyback just finished.  Release the timing gen:
                   vid_enable             <= 1;
                   doing_resync           <= 0;
                   // Ack request:
                   config_sync_ack        <= ~config_sync_ack;
           end
   end // always @ (posedge pclk)


   ////////////////////////////////////////////////////////////////////////////////
   // Line buffer:

   /* Buffer 0 is used for line 0, 2, 4, etc., buffer 1 used for line 1, 3, 5, etc.
    * The input DMA is written to buffer 0 first, then wrapping to alternate buffers.
    * The output scan selects a buffer based on line number, and starts a line
    * later than the input scan (so that the first buffer is full by the time the
    * display starts).
    */
   reg [31:0] 	line_buffer[(256*2)-1:0]; // 2x 1KB buffers

   /* Note pulses for load_dma etc. are in the load_dma_clk
    * domain.  (This should be slower than pclk... but beware!)
    */

   reg [8:0] 	line_w_ptr;
   reg [2:0] 	dclk_sync_fb;
   wire      	flyback_falling2 = dclk_sync_fb[1] == 0 && dclk_sync_fb[2] == 1;

   always @(posedge load_dma_clk) begin
           // Synchronise flyback into load_dma_clk domain:
           dclk_sync_fb 	<= {dclk_sync_fb[1:0], sync_flyback};

           if (flyback_falling2) begin
                   /* At frame start, reset to beginning of buffer 0: */
                   line_w_ptr <= 0;
           end else if (load_dma) begin
                   /* At the end of a line in, wrap to next buffer: */
                   if (line_w_ptr[7:0] != t_words_per_line_m1)
                     line_w_ptr            <= line_w_ptr + 1;
                   else
                     line_w_ptr            <= {~line_w_ptr[8], 8'h00};
                   line_buffer[line_w_ptr] <= load_dma_data;
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Cursor buffer:

   /* Don't need double-buffering, because 4 beats (16 bytes) of cursor data is loaded
    * every other line, before the cursor is displayed.
    */
   reg [31:0] 	cursor_buffer[3:0];	// Need to store 4 beats from hsync time
   reg [1:0]  	cursor_w_ptr;

   always @(posedge load_dma_clk) begin
           if (flyback_falling2) begin
                   /* At frame start, reset to beginning of buffer 0: */
                   cursor_w_ptr <= 0;
           end else if (load_dma_cursor) begin
                   if (cursor_w_ptr == 3)
                     cursor_w_ptr <= 0;
                   else
                     cursor_w_ptr <= cursor_w_ptr + 1;
                   cursor_buffer[cursor_w_ptr] <= load_dma_data;
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Frame timing configuration

   /* In this component, the syncs are at the start of the H or V scan, i.e.
    * at coordinate 0, and display starts some pixels/lines into the scan.
    * E.g. H=0 has HSYNC asserted, which turns off when the back porch is entered,
    * which completes as the display line starts.
    */
   reg [ctr_width_x-1:0]	ti_h_sync_off;
   reg [ctr_width_x-1:0]	ti_h_disp_start;
   reg [ctr_width_x-1:0]        ti_h_disp_end;
   reg [ctr_width_x-1:0]        ti_h_total;
   reg [ctr_width_y-1:0]	ti_v_sync_off;
   reg [ctr_width_y-1:0]	ti_v_disp_start;
   reg [ctr_width_y-1:0]        ti_v_disp_end;
   reg [ctr_width_y-1:0]        ti_v_total;
   reg                          en_hires;
   reg [2:0]                    bpp;
   reg                          double_x;
   reg                          double_y;

   /* Timing configuration */
   always @(posedge pclk) begin
           // To initialise new timing, hold clk_pixel_ena=0 for 3 cycles:
           if (!vid_enable) begin
                   ti_h_sync_off   <= t_horiz_sync_width - 1;
                   ti_h_disp_start <= t_horiz_sync_width + t_horiz_bp - 1;
                   ti_h_disp_end   <= t_horiz_sync_width + t_horiz_bp + t_horiz_res - 1;
                   ti_h_total      <= t_horiz_sync_width + t_horiz_bp + t_horiz_res + t_horiz_fp - 1;

                   ti_v_sync_off   <= t_vert_sync_width - 1;
                   ti_v_disp_start <= t_vert_sync_width + t_vert_bp - 1;
                   ti_v_disp_end   <= t_vert_sync_width + t_vert_bp + t_vert_res - 1;
                   ti_v_total      <= t_vert_sync_width + t_vert_bp + t_vert_res + t_vert_fp - 1;

                   en_hires       <= t_hires;
                   bpp            <= t_bpp;
                   double_x       <= t_double_x;
                   double_y       <= t_double_y;
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Capture of dynamic configuration

   /* Initially, this means cursor, but eventually palette etc. will have to
    * come in from the outside.  If we say it mustn't change outside of flyback,
    * it's easier to synchronise (this is OK for cursor, not OK for palette).
    */
   reg [10:0] 	cursor_x;
   reg [10:0] 	cursor_xend;
   reg [9:0] 	cursor_y;
   reg [9:0] 	cursor_yend;

   always @(posedge pclk) begin
           if (flyback_falling) begin
                   // These values are the px value before which the cursor appears/ends:
                   cursor_x    <= (double_x ? {v_cursor_x, 1'b0} : v_cursor_x) +
                                  ti_h_disp_start;
                   cursor_xend <= (double_x ? {v_cursor_x, 1'b0} : v_cursor_x) +
                                  ti_h_disp_start + (double_x ? 64 : 32);
                   // The y coordinate is the py value before the cursor start/end line:
                   cursor_y    <= (double_y ? {v_cursor_y, 1'b0} : v_cursor_y) +
                                  ti_v_disp_start;
                   cursor_yend <= (double_y ? {v_cursor_yend, 1'b0} : v_cursor_yend) +
                                  ti_v_disp_start;
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Output frame timing and sync generation

   reg [ctr_width_x-1:0]	px;
   reg [ctr_width_y-1:0]        py;
   reg                          hsync;
   reg                          vsync;
   reg                          de;
   reg                          v_on_display;

   /* Convenience counters for actual pixel addresses.  Note dispx/dispy
    * counters move every other (output) pixel when pixel/line doubling
    * is enabled:
    */
   reg [ctr_width_x:0]		internal_dispx;
   reg [ctr_width_y:0]        	internal_dispy;
   wire [ctr_width_x-1:0]	dispx;
   wire [ctr_width_y-1:0]       dispy;

   always @(posedge pclk) begin
           if (!vid_enable) begin
                   /* A sync "resets" to the line before the first horizontal
                    * line on display.  When doubling lines, reset to -2 so
                    * that the DMA in completes the line before 2 are scanned out.
                    */
                   px              <= {ctr_width_x{1'b0}};
                   py              <= ti_v_disp_start - { {ctr_width_y-1{1'b0}}, double_y }; // -0 or -1
                   hsync           <= 1;
                   vsync           <= 0;
                   de              <= 0;
                   v_on_display    <= 1;
                   internal_dispx  <= 0;
                   internal_dispy  <= 0;
           end else if (px == ti_h_total) begin
                   px      <= 0;
                   hsync   <= 1;
                   de      <= 0;

                   if (py == ti_v_total) begin
                           py           <= 0;
                           vsync        <= 1;
                   end else begin
                           py    <= py + 1;

                           if (py == ti_v_disp_start) begin
                                   v_on_display <= 1;
                           end else if (py == ti_v_disp_end) begin
                                   v_on_display 	<= 0;
                                   internal_dispy 	<= 0;
                           end else if (v_on_display) begin
                                   internal_dispy 	<= internal_dispy + 1;
                           end

                           if (py == ti_v_sync_off)
                             vsync <= 0;
                   end
           end else begin
                   px    <= px + 1;
                   if (de)
                     internal_dispx <= internal_dispx + 1;
                   else
                     internal_dispx <= 0;

                   // Syncs:
                   if (px == ti_h_sync_off)
                     hsync <= 0;

                   if (px == ti_h_disp_start && v_on_display)
                     de <= 1;

                   if (px == ti_h_disp_end)
                     de <= 0;
           end
   end // always @ (posedge pclk)

   // The actual logical pixel address:
   assign dispx = double_x ? internal_dispx[ctr_width_x:1] :
                  internal_dispx[ctr_width_x-1:0];
   assign dispy = double_y ? internal_dispy[ctr_width_y:1] :
                  internal_dispy[ctr_width_y-1:0];


   ////////////////////////////////////////////////////////////////////////////////
   // Output sync signals

   /* The coordinates dispx/dispy/px/py are aligned (in time) with de/hsync/vsync.
    * If they're used as a RAM access (as they will be), its output will be delayed
    * and shifted relative to those signals.  So, they must be delayed too.
    *
    * There are 4 stages of output pipeline, accommodating linebuffer and palette
    * access plus pixel reformatting.
    */
   reg       	hsync_delayed, vsync_delayed, de_delayed;
   reg       	hsync_delayed2, vsync_delayed2, de_delayed2, blank_delayed2;
   reg          hsync_delayed3, vsync_delayed3, de_delayed3, blank_delayed3;
   reg          hsync_delayed4, vsync_delayed4, de_delayed4, blank_delayed4;

   always @(posedge pclk) begin
           hsync_delayed  <= hsync;
           vsync_delayed  <= vsync;
           de_delayed     <= de;

           hsync_delayed2 <= hsync_delayed;
           vsync_delayed2 <= vsync_delayed;
           de_delayed2    <= de_delayed;
           blank_delayed2 <= ~de_delayed;

           hsync_delayed3 <= hsync_delayed2;
           vsync_delayed3 <= vsync_delayed2;
           de_delayed3    <= de_delayed2;
           blank_delayed3 <= blank_delayed2;

           hsync_delayed4 <= hsync_delayed3;
           vsync_delayed4 <= vsync_delayed3;
           de_delayed4    <= de_delayed3;
           blank_delayed4 <= blank_delayed3;
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Test image generator

   // These signals are aligned in time with hsync_delayed and friends.
   reg [7:0] 	tc_r;
   reg [7:0] 	tc_g;
   reg [7:0] 	tc_b;

   // These signals are aligned in time with hsync_delayed2 and friends.
   reg [7:0] 	tc_r2;
   reg [7:0] 	tc_g2;
   reg [7:0] 	tc_b2;

   // These signals are aligned in time with hsync_delayed3 and friends.
   reg [7:0] 	tc_r3;
   reg [7:0] 	tc_g3;
   reg [7:0] 	tc_b3;

   wire      	stripex = (px == (ti_h_disp_start+1)) ||
                (px == (ti_h_disp_end)) || (px[7:0] == 8'h00);
   wire      	stripey = (py == (ti_v_disp_start+1)) ||
                (py == ti_v_disp_end) || (py[7:0] == 8'h00);
   wire [7:0] 	stripe = (stripex || stripey) ? 8'hff : 8'h0;

   always @(posedge pclk) begin
           tc_r <= dispx[7:0] | stripe;
           tc_g <= dispy[7:0] | stripe;
           tc_b <= (dispx[8:1] ^ dispy[8:1]) | stripe;

           tc_r2 	<= tc_r;
           tc_g2 	<= tc_g;
           tc_b2 	<= tc_b;

           tc_r3 	<= tc_r2;
           tc_g3 	<= tc_g2;
           tc_b3 	<= tc_b2;
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Cursor video data

   reg [31:0] 	cursor_data;
   reg        	on_cursor_x;
   reg        	on_cursor_y;
   reg [5:0]  	internal_cursor_disp_x;
   reg [10:0] 	internal_cursor_disp_y;	 // FIXME: make smaller
   wire [4:0] 	cursor_disp_x;
   wire [9:0] 	cursor_disp_y;
   reg [3:0]  	cxidx;
   reg        	was_cursor_pix;
   reg        	was_cursor_pix2;
   reg [1:0] 	cursor_pixel; // Wire
   reg [1:0] 	cursor_pixel_hr; // Wire
   reg [1:0]    cursor_pixel2;
   reg [1:0]    cursor_pixel2_hr;
   // This logic culminates in this signal, valid aligned with hsync_delayed3 et al:
   reg [1:0]    cursor_pixel3;

   always @(posedge pclk) begin
           if (px == ti_h_total && py == ti_v_total) begin
                   on_cursor_x   <= 0;
                   on_cursor_y   <= 0;
           end else begin
                   if (py == cursor_y) begin
                           internal_cursor_disp_y <= 0;
                           on_cursor_y <= 1;
                   end
                   if (py == cursor_yend) begin
                           on_cursor_y <= 0;
                   end
                   if (px == cursor_x) begin
                           internal_cursor_disp_x <= 0;
                           on_cursor_x   <= 1;
                   end
                   if (px == cursor_xend) begin
                           on_cursor_x   <= 0;
                           if (on_cursor_y)
                             internal_cursor_disp_y <= internal_cursor_disp_y + 1;
                   end

                   if (on_cursor_x)
                     internal_cursor_disp_x <= internal_cursor_disp_x + 1;
           end

           /* The buffer contains 16 bytes, i.e. 64 pixels, i.e. 2 lines.
            * Line 0 is bytes 0-7 (words 0-1), line 1 is bytes 8-15 (words 2-3).
            */
           cursor_data    	<= cursor_buffer[ {cursor_disp_y[0], cursor_disp_x[4]} ];
           cxidx          	<= cursor_disp_x[3:0];
           was_cursor_pix 	<= on_cursor_x && on_cursor_y;

           was_cursor_pix2 	<= was_cursor_pix;
   end // always @ (posedge pclk)

   // The logical cursor pixel coordinates:
   assign 	cursor_disp_x = double_x ? internal_cursor_disp_x[5:1] :
                                internal_cursor_disp_x[4:0];
   assign 	cursor_disp_y = double_y ? internal_cursor_disp_y[10:1] :
                                internal_cursor_disp_y[9:0];

   always @(*) begin
           cursor_pixel = 2'b00;

           case (cxidx)
             4'h0:	cursor_pixel = cursor_data[1:0];
             4'h1:	cursor_pixel = cursor_data[3:2];
             4'h2:	cursor_pixel = cursor_data[5:4];
             4'h3:	cursor_pixel = cursor_data[7:6];
             4'h4:	cursor_pixel = cursor_data[9:8];
             4'h5:	cursor_pixel = cursor_data[11:10];
             4'h6:	cursor_pixel = cursor_data[13:12];
             4'h7:	cursor_pixel = cursor_data[15:14];
             4'h8:	cursor_pixel = cursor_data[17:16];
             4'h9:	cursor_pixel = cursor_data[19:18];
             4'ha:	cursor_pixel = cursor_data[21:20];
             4'hb:	cursor_pixel = cursor_data[23:22];
             4'hc:	cursor_pixel = cursor_data[25:24];
             4'hd:	cursor_pixel = cursor_data[27:26];
             4'he:	cursor_pixel = cursor_data[29:28];
             default:	cursor_pixel = cursor_data[31:30];
           endcase // case (cxidx)
   end

   always @(posedge pclk) begin
           cursor_pixel2 	<= cursor_pixel;
           cursor_pixel3 	<= !was_cursor_pix2 ? 2'b00 : cursor_pixel2;
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Video data

`ifdef INCLUDE_HIGH_COLOUR
   /* Prototyping:  Extend the 256 colour palette to 24bits.
    *
    * This needs a better solution for 1/2/4bpp modes, e.g. a VIDC control reg
    * extension bit causing them to use this RAM instead of getting the palette
    * from vidc_palette.  Alternatively, pipe VIDC palette writes through to
    * this RAM.
    */
   reg [23:0] 	palette8b [255:0];
   initial $readmemh("palette24.mem", palette8b);

   /* Capture special-reg writes into this palette:
    */
   always @(posedge load_dma_clk) begin
           if (vidc_special_written) begin
                   if (vidc_special[11:8] == 4'h0) begin
                           palette8b[vidc_special[7:0]] <= vidc_special_data;
                   end
           end
   end
`define INTERNAL_RGB 24
`else
   reg [11:0] 	palette8b [255:0];
   initial $readmemh("palette.mem", palette8b);
 `define INTERNAL_RGB 12
`endif

   /* Generate video image: */
   reg [31:0] 	rdata;
   reg [4:0]  	xidx;

   wire [8:0] 	read_line_idx = (bpp == 0) ? /* 1BPP */
                {dispy[0], 2'b00, dispx[ctr_width_x-1:5]} :
                (bpp == 1) ? /* 2BPP */
                {dispy[0], 1'b0, dispx[ctr_width_x-1:4]} :
                (bpp == 2) ? /* 4BPP */
                {dispy[0], dispx[ctr_width_x-1:3]} :
`ifdef INCLUDE_HIGH_COLOUR
                (bpp == 3) ? /* 8BPP */
                {dispy[0], dispx[9:2]} :
                {dispy[0], dispx[8:1]}; /* 16BPP */
`else
                {dispy[0], dispx[9:2]}; /* 8BPP */
`endif

   /* Read the video RAM, indexed by X scaled by BPP: */
   always @(posedge pclk) begin
           rdata 	<= line_buffer[read_line_idx];
           xidx  	<= dispx[4:0];
   end

   /* Pixel selection/reformatting: */

   reg 		read_1b_pixel;
   reg [3:0]    read_124b_pixel;
   reg [`INTERNAL_RGB-1:0]	read_8b_pixel_rgb;
   reg          read_1b_pixel_d; // wire
   reg [1:0]    read_2b_pixel_d; // wire
   reg [3:0]    read_4b_pixel_d; // wire
   reg [7:0]    read_8b_pixel_d; // wire

   /* Replacing the ternary ops with these case statements gave a significant perf
    * improvement; yosys seems to do a much better job with these.
    */
   always @(*) begin
           read_1b_pixel_d 	= 0;
           case (xidx[4:0])
             0: read_1b_pixel_d       	= rdata[0];
             1: read_1b_pixel_d       	= rdata[1];
             2: read_1b_pixel_d       	= rdata[2];
             3: read_1b_pixel_d       	= rdata[3];
             4: read_1b_pixel_d       	= rdata[4];
             5: read_1b_pixel_d       	= rdata[5];
             6: read_1b_pixel_d       	= rdata[6];
             7: read_1b_pixel_d       	= rdata[7];
             8: read_1b_pixel_d       	= rdata[8];
             9: read_1b_pixel_d       	= rdata[9];
             10: read_1b_pixel_d      	= rdata[10];
             11: read_1b_pixel_d      	= rdata[11];
             12: read_1b_pixel_d      	= rdata[12];
             13: read_1b_pixel_d      	= rdata[13];
             14: read_1b_pixel_d      	= rdata[14];
             15: read_1b_pixel_d      	= rdata[15];
             16: read_1b_pixel_d      	= rdata[16];
             17: read_1b_pixel_d      	= rdata[17];
             18: read_1b_pixel_d      	= rdata[18];
             19: read_1b_pixel_d      	= rdata[19];
             20: read_1b_pixel_d      	= rdata[20];
             21: read_1b_pixel_d      	= rdata[21];
             22: read_1b_pixel_d      	= rdata[22];
             23: read_1b_pixel_d      	= rdata[23];
             24: read_1b_pixel_d      	= rdata[24];
             25: read_1b_pixel_d      	= rdata[25];
             26: read_1b_pixel_d      	= rdata[26];
             27: read_1b_pixel_d      	= rdata[27];
             28: read_1b_pixel_d      	= rdata[28];
             29: read_1b_pixel_d      	= rdata[29];
             30: read_1b_pixel_d      	= rdata[30];
             default: read_1b_pixel_d 	= rdata[31];
           endcase // case (xidx[4:0])

           read_2b_pixel_d 	= 0;
           case (xidx[3:0])
             0: read_2b_pixel_d 	= rdata[1:0];
             1: read_2b_pixel_d 	= rdata[3:2];
             2: read_2b_pixel_d 	= rdata[5:4];
             3: read_2b_pixel_d 	= rdata[7:6];
             4: read_2b_pixel_d 	= rdata[9:8];
             5: read_2b_pixel_d 	= rdata[11:10];
             6: read_2b_pixel_d 	= rdata[13:12];
             7: read_2b_pixel_d 	= rdata[15:14];
             8: read_2b_pixel_d 	= rdata[17:16];
             9: read_2b_pixel_d 	= rdata[19:18];
             10: read_2b_pixel_d 	= rdata[21:20];
             11: read_2b_pixel_d 	= rdata[23:22];
             12: read_2b_pixel_d 	= rdata[25:24];
             13: read_2b_pixel_d 	= rdata[27:26];
             14: read_2b_pixel_d 	= rdata[29:28];
             default: read_2b_pixel_d 	= rdata[31:30];
           endcase // case (xidx[3:0])

           read_4b_pixel_d	= 0;
           case (xidx[2:0])
             0: read_4b_pixel_d 	= rdata[3:0];
             1: read_4b_pixel_d 	= rdata[7:4];
             2: read_4b_pixel_d 	= rdata[11:8];
             3: read_4b_pixel_d 	= rdata[15:12];
             4: read_4b_pixel_d 	= rdata[19:16];
             5: read_4b_pixel_d 	= rdata[23:20];
             6: read_4b_pixel_d 	= rdata[27:24];
             default: read_4b_pixel_d 	= rdata[31:28];
           endcase // case (xidx[2:0])

           read_8b_pixel_d	= 0;
           case (xidx[1:0])
             0:	read_8b_pixel_d       	= rdata[7:0];
             1: read_8b_pixel_d       	= rdata[15:8];
             2: read_8b_pixel_d       	= rdata[23:16];
             default: read_8b_pixel_d 	= rdata[31:24];
           endcase // case (xidx[1:0])
   end // always @ (*)

`ifdef INCLUDE_HIGH_COLOUR
   reg  [23:0]   read_16b_pixel_rgb;
   wire [15:0]   read_16b_pixel_d;

   assign read_16b_pixel_d 		= xidx[0] ? rdata[31:16] : rdata[15:0];
   always @(posedge pclk) begin
           read_16b_pixel_rgb <= { read_16b_pixel_d[15:11], {3{read_16b_pixel_d[11]}},
                                   read_16b_pixel_d[10:5],  {2{read_16b_pixel_d[5]}},
                                   read_16b_pixel_d[4:0],   {3{read_16b_pixel_d[0]}} };
   end
`endif

   // These signals are aligned with hsync_delayed2 et al:
   always @(posedge pclk) begin
           read_1b_pixel     <= read_1b_pixel_d;
           read_8b_pixel_rgb <= palette8b[read_8b_pixel_d];

           read_124b_pixel   <= (bpp == 0) ? {3'h0, read_1b_pixel_d} :
                                (bpp == 1) ? {2'h0, read_2b_pixel_d} :
                                read_4b_pixel_d;
   end

   reg [11:0] 	vidc_palette_out; // Wire

   /* This is an unsynchronised read of regs from another clock domain,
    * achtung! */
   always @(*) begin
           vidc_palette_out = 0;

           case (read_124b_pixel)
             4'h0:	vidc_palette_out = vidc_palette[(12*1)-1:(12*0)];
             4'h1:	vidc_palette_out = vidc_palette[(12*2)-1:(12*1)];
             4'h2:	vidc_palette_out = vidc_palette[(12*3)-1:(12*2)];
             4'h3:	vidc_palette_out = vidc_palette[(12*4)-1:(12*3)];
             4'h4:	vidc_palette_out = vidc_palette[(12*5)-1:(12*4)];
             4'h5:	vidc_palette_out = vidc_palette[(12*6)-1:(12*5)];
             4'h6:	vidc_palette_out = vidc_palette[(12*7)-1:(12*6)];
             4'h7:	vidc_palette_out = vidc_palette[(12*8)-1:(12*7)];
             4'h8:	vidc_palette_out = vidc_palette[(12*9)-1:(12*8)];
             4'h9:	vidc_palette_out = vidc_palette[(12*10)-1:(12*9)];
             4'ha:	vidc_palette_out = vidc_palette[(12*11)-1:(12*10)];
             4'hb:	vidc_palette_out = vidc_palette[(12*12)-1:(12*11)];
             4'hc:	vidc_palette_out = vidc_palette[(12*13)-1:(12*12)];
             4'hd:	vidc_palette_out = vidc_palette[(12*14)-1:(12*13)];
             4'he:	vidc_palette_out = vidc_palette[(12*15)-1:(12*14)];
             default:	vidc_palette_out = vidc_palette[(12*16)-1:(12*15)];
           endcase
   end

   // These signals are aligned with hsync_delayed3 et al:
   reg [`INTERNAL_RGB-1:0] 	read_pixel3;

   always @(posedge pclk) begin
`ifdef INCLUDE_HIGH_COLOUR
           if (bpp == 4) begin
                   read_pixel3 	<= read_16b_pixel_rgb;
           end else
`endif
           if (bpp == 3) begin
                   read_pixel3 	<= read_8b_pixel_rgb;
           end else if (en_hires) begin
                   read_pixel3 	<= read_1b_pixel ? {`INTERNAL_RGB{1'b0}} : {`INTERNAL_RGB{1'b1}};
           end else begin // regular 1, 2, 4bpp:
`ifdef INCLUDE_HIGH_COLOUR
             read_pixel3 <= { vidc_palette_out[11:8], {4{vidc_palette_out[8]}},
                              vidc_palette_out[7:4],  {4{vidc_palette_out[4]}},
                              vidc_palette_out[3:0],  {4{vidc_palette_out[0]}} };
`else
             read_pixel3 <= vidc_palette_out;
`endif
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Final video output pipeline stage

   /* Overlay cursor onto video: (false colour for mode 23 :) ) */
   wire [11:0] cursor_col0int            = en_hires ? 12'hff0 :
               vidc_cursor_palette[(12*0)+11:(12*0)];
   wire [11:0] cursor_col1int            = vidc_cursor_palette[(12*1)+11:(12*1)];
   wire [11:0] cursor_col2int            = en_hires ? 12'h900 :
               vidc_cursor_palette[(12*2)+11:(12*2)];
`ifdef INCLUDE_HIGH_COLOUR
   wire [23:0] cursor_col0 = { cursor_col0int[11:8], {4{cursor_col0int[8]}},
                               cursor_col0int[7:4],  {4{cursor_col0int[4]}},
                               cursor_col0int[3:0],  {4{cursor_col0int[0]}} };
   wire [23:0] cursor_col1 = { cursor_col1int[11:8], {4{cursor_col1int[8]}},
                               cursor_col1int[7:4],  {4{cursor_col1int[4]}},
                               cursor_col1int[3:0],  {4{cursor_col1int[0]}} };
   wire [23:0] cursor_col2 = { cursor_col2int[11:8], {4{cursor_col2int[8]}},
                               cursor_col2int[7:4],  {4{cursor_col2int[4]}},
                               cursor_col2int[3:0],  {4{cursor_col2int[0]}} };
`else
   wire [11:0] cursor_col0 = cursor_col0int;
   wire [11:0] cursor_col1 = cursor_col1int;
   wire [11:0] cursor_col2 = cursor_col2int;
`endif
   wire [`INTERNAL_RGB-1:0] final_pixel_rgb 	= cursor_pixel3 == 2'b00 ? read_pixel3 :
               (cursor_pixel3 == 2'b01) ? cursor_col0 :
               (cursor_pixel3 == 2'b10) ? cursor_col1 :
               cursor_col2;
   wire [3:0]  final_pixel_r = final_pixel_rgb[3:0];
   wire [3:0]  final_pixel_g = final_pixel_rgb[7:4];
   wire [3:0]  final_pixel_b = final_pixel_rgb[11:8];

   /* These output signals are aligned with hsync_delayed4 et al: */
   reg [7:0]    o_r_delayed4;
   reg [7:0]    o_g_delayed4;
   reg [7:0]    o_b_delayed4;

   always @(posedge pclk) begin
           /* Select between test card & 4-to-8 expanded video data: */
`ifdef INCLUDE_HIGH_COLOUR
           o_r_delayed4 <= (enable_test_card) ? tc_r3 : final_pixel_rgb[7:0];
           o_g_delayed4 <= (enable_test_card) ? tc_g3 : final_pixel_rgb[15:8];
           o_b_delayed4 <= (enable_test_card) ? tc_b3 : final_pixel_rgb[23:16];
`else
           o_r_delayed4 <= (enable_test_card) ? tc_r3 : {final_pixel_r[3:0], {4{final_pixel_r[3]}}};
           o_g_delayed4 <= (enable_test_card) ? tc_g3 : {final_pixel_g[3:0], {4{final_pixel_g[3]}}};
           o_b_delayed4 <= (enable_test_card) ? tc_b3 : {final_pixel_b[3:0], {4{final_pixel_b[3]}}};
`endif
   end

   assign o_r 		= o_r_delayed4;
   assign o_g 		= o_g_delayed4;
   assign o_b 		= o_b_delayed4;
   assign o_hsync 	= hsync_delayed4;
   assign o_vsync 	= vsync_delayed4;
   assign o_de 		= de_delayed4;
   assign o_blank 	= blank_delayed4;

endmodule // video_timing
