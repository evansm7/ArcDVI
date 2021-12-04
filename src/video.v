/* ArcDVI: Wrap up output video timing, config, etc.
 *
 * Provides a read/write interface to internal configuration registers,
 * expected to be set up by an external MCU.
 *
 * Synchronises against external VIDC video timing, and displays the
 * VIDC DMA streams.
 *
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

module video(input wire		      clk,
             input wire               reset,

             // Register access
             input wire [31:0]        reg_wdata,
             output wire [31:0]       reg_rdata,
             input wire [5:0]         reg_addr, /* Note 1:0 ignored */
             input wire               reg_wstrobe,

             // DMA
             input wire               load_dma,
             input wire               load_dma_cursor,
             input wire [31:0]        load_dma_data,
             // Config
             input wire [10:0]        v_cursor_x, // Note, raw
             input wire [9:0]         v_cursor_y,
             input wire [9:0]         v_cursor_yend,

             input wire [(16*12)-1:0] vidc_palette,
             input wire [(3*12)-1:0]  vidc_cursor_palette,

             input wire               vidc_special_written,
             input wire [23:0]        vidc_special,
             input wire [23:0]        vidc_special_data,

             input wire               vidc_tregs_status,
             output reg               vidc_tregs_ack,

             // Pixel/shift clock-related signals
             input wire               clk_pixel,
             input wire               clk_shift,
             // Video data output:
             output wire [7:0]        video_r,
             output wire [7:0]        video_g,
             output wire [7:0]        video_b,
             output wire              video_hsync,
             output wire              video_vsync,
             output wire              video_blank,

             // DMA clock-related signals
             input wire               enable_test_card,

             // Async
             input wire               sync_flybk,

             // Export some interesting config stuff:
             output wire              is_hires
             );

   ////////////////////////////////////////////////////////////////////////////////
   // Output video timing configuration registers:

   // FIXME: vs/hs params can all be smaller!
   reg [10:0]           c_res_x;
   reg [10:0]           c_hs_fp;
   reg [10:0]           c_hs_width;
   reg [10:0]           c_hs_bp;
   reg [10:0]           c_res_y;
   reg [10:0]           c_vs_fp;
   reg [10:0]           c_vs_width;
   reg [10:0]           c_vs_bp;
   reg 			c_sync;
   reg                  c_hires;
   reg [7:0]            c_wpl_m1;
   reg [2:0]            c_bpp;
   reg                  c_double_x;
   reg                  c_double_y;
   reg [10:0]           c_cursor_x_offset;

   always @(posedge clk) begin
           if (reset) begin
                   /* Default timing:
                    *
                    * Goal is to create an identical horizontal scan period compared
                    * to the Arc at 96MHz, but with a lower pixel clock.
                    *
                    * 96 is 24*4 (from Arc 24MHz VIDC clock).
                    * 72MHz is 24*3, and 84MHz is 24*3.5.
                    *
                    * Mode 23 is 1568 px cycle (HCR=0xc3=195=390/2),
                    * meaning horiz is 392px (x4 becomes 1568).
                    *
                    * Same horiz period matched by:
                    * - At 72MHz, 1176 (blanking of 24, too low)
                    * - At 80MHz, comes out as 1306.6666 ;(
                    * - At 78MHz (x3.25), 1274 (blanking 122).  Yes! 40/20/62.
                    */
`ifdef HIRES_MODE
                   c_wpl_m1          <= (1152/8/4)-1;
                   c_res_x           <= 1152;
                   c_res_y           <= 896;
                   c_hs_fp           <= 40;
                   c_hs_width        <= 20;
                   c_hs_bp           <= 62; // 40+20+62=122
                   c_vs_fp           <= 4;
                   c_vs_width        <= 3;
                   c_vs_bp           <= 47;
                   c_cursor_x_offset <= (11'h44*4);
                   c_hires           <= 1;
                   c_bpp             <= 0; // log2 of
                   c_double_x        <= 0;
                   c_double_y        <= 0;
`else // !`ifdef HIRES_MODE
                   // Roughly, mode 12 as somewhere to start:
                   c_wpl_m1          <= (640/2/4)-1;
                   c_res_x           <= 640;
                   c_res_y           <= 256;
                   c_hs_fp           <= 40;
                   c_hs_width        <= 20;
                   c_hs_bp           <= 768-640-40-20;
                   c_vs_fp           <= 40;
                   c_vs_width        <= 5;
                   c_vs_bp           <= 624-512-5-40;
                   c_cursor_x_offset <= 217;
                   c_hires           <= 0;
                   c_bpp             <= 2; // log2 of
                   c_double_x        <= 0;
                   c_double_y        <= 1;
`endif // !`ifdef HIRES_MODE

                   c_sync            <= 0;
                   vidc_tregs_ack    <= 0;

           end else if (reg_wstrobe) begin
                   case (reg_addr[5:2])
                     4'h0: begin
                             c_res_x    <= reg_wdata[10:0];
                             c_double_x <= reg_wdata[31];
                     end
                     4'h1:      c_hs_fp                      <= reg_wdata[10:0];
                     4'h2:      c_hs_width                   <= reg_wdata[10:0];
                     4'h3:      c_hs_bp                      <= reg_wdata[10:0];
                     4'h4: begin
                             c_res_y    <= reg_wdata[10:0];
                             c_double_y <= reg_wdata[31];
                     end
                     4'h5:      c_vs_fp                      <= reg_wdata[10:0];
                     4'h6:      c_vs_width                   <= reg_wdata[10:0];
                     4'h7:      c_vs_bp                      <= reg_wdata[10:0];
                     4'h8: begin
                             c_sync         <= reg_wdata[0];
                             vidc_tregs_ack <= reg_wdata[2];
                     end
                     4'h9:	c_wpl_m1                     <= reg_wdata[7:0];
                     4'ha:	{c_hires, c_bpp,
                                 c_cursor_x_offset} <= { reg_wdata[31:28],
                                                         reg_wdata[10:0] };
                   endcase
           end
   end

   // Synchroniser for sync_ack from the clk_pixel domain:
   wire c_sync_ack_p;
   reg [1:0] sync_ack_ss;
   always @(posedge clk) begin
           sync_ack_ss 		<= {sync_ack_ss[0], c_sync_ack_p};
   end
   wire c_sync_ack      	= sync_ack_ss[1];

   // Synchroniser for flyback:
   reg [1:0] sync_flybk_ss;
   always @(posedge clk) begin
           sync_flybk_ss 	<= {sync_flybk_ss[0], sync_flybk};
   end
   wire c_flybk         	= sync_flybk_ss[1];

   assign reg_rdata 		= reg_addr[5:2] == 4'h0 ? {c_double_x, 20'h0, c_res_x} :
                                  reg_addr[5:2] == 4'h1 ? {21'h0, c_hs_fp} :
                                  reg_addr[5:2] == 4'h2 ? {21'h0, c_hs_width} :
                                  reg_addr[5:2] == 4'h3 ? {21'h0, c_hs_bp} :
                                  reg_addr[5:2] == 4'h4 ? {c_double_y, 20'h0, c_res_y} :
                                  reg_addr[5:2] == 4'h5 ? {21'h0, c_vs_fp} :
                                  reg_addr[5:2] == 4'h6 ? {21'h0, c_vs_width} :
                                  reg_addr[5:2] == 4'h7 ? {21'h0, c_vs_bp} :
                                  reg_addr[5:2] == 4'h8 ? {27'h0, c_flybk,
                                                           vidc_tregs_status, vidc_tregs_ack,
                                                           c_sync_ack, c_sync} :
                                  reg_addr[5:2] == 4'h9 ? {24'h0, c_wpl_m1} :
                                  reg_addr[5:2] == 4'ha ? {c_hires, c_bpp, 17'h0, c_cursor_x_offset} :
                                  32'h0;

   assign is_hires 	 	= c_hires;

   // Apply magic number to move the cursor.  FIXME, derive this from VIDC regs...
   wire [10:0] norm_cursor_x  	= v_cursor_x - c_cursor_x_offset;


   ////////////////////////////////////////////////////////////////////////////////
   // Video & timing generator

   video_timing VTI(
                    .pclk(clk_pixel),

                    .o_r(video_r),
                    .o_g(video_g),
                    .o_b(video_b),
                    .o_hsync(video_hsync),
                    .o_vsync(video_vsync),
                    .o_blank(video_blank),

                    .load_dma_clk(clk),
                    .load_dma(load_dma),
                    .load_dma_cursor(load_dma_cursor),
                    .load_dma_data(load_dma_data),

                    .vidc_palette(vidc_palette),
                    .vidc_cursor_palette(vidc_cursor_palette),

                    .vidc_special_written(vidc_special_written),
                    .vidc_special(vidc_special),
                    .vidc_special_data(vidc_special_data),

                    .v_cursor_x(norm_cursor_x),
                    .v_cursor_y(v_cursor_y),
                    .v_cursor_yend(v_cursor_yend),

                    .t_horiz_res(c_res_x),
                    .t_horiz_fp(c_hs_fp),
                    .t_horiz_sync_width(c_hs_width),
                    .t_horiz_bp(c_hs_bp),

                    .t_vert_res(c_res_y),
                    .t_vert_fp(c_vs_fp),
                    .t_vert_sync_width(c_vs_width),
                    .t_vert_bp(c_vs_bp),

                    .t_words_per_line_m1(c_wpl_m1),
                    .t_hires(c_hires),
                    .t_bpp(c_bpp),
                    .t_double_x(c_double_x),
                    .t_double_y(c_double_y),

                    .sync_flyback(sync_flybk),
                    .config_sync_req(c_sync),
                    .config_sync_ack(c_sync_ack_p),

                    .enable_test_card(enable_test_card)
                    );

endmodule
