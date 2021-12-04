/* ArcDVI top-level
 *
 * This project interfaces to the Acorn Archimedes VIDC, passively tracking
 * when the Arc writes VIDC registers and when the VIDC receives DMA.
 *
 * The DMA is repackaged and streamed out in a possibly-upscaled/retimed fashion.
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

module soc_top(input wire        clk_25mhz,
               input wire        btn,
               input wire [3:0]  sw,
               output wire       led,
               output wire [3:0] gpdi_dp,
               input wire        ser_rx,
               output wire       ser_tx,
               input wire [31:0] vidc_d,
               input wire        vidc_nvidw,
               input wire        vidc_nvcs,
               input wire        vidc_nhs,
               input wire        vidc_nsndrq,
               input wire        vidc_nvidrq,
               input wire        vidc_flybk,
               input wire        vidc_ckin,
               input wire        vidc_nsndak,
               input wire        vidc_nvidak
               );

   parameter CLK_RATE = 50000000;
   parameter BAUD_RATE = 115200;

   ////////////////////////////////////////////////////////////////////////////////
   /* Clocks and reset */

   wire                          clk, clk_pixel, clk_shift;

   /* Two PLLs: One generates system/CPU clock from crystal input.
    * The other generates the video output/pixel clock from the VIDC
    * clock.
    */

`ifdef HIRES_MODE
   localparam pixel_freq = 24000000*3.25;
`else
   localparam pixel_freq = 24000000;
`endif

   clocks #(.VIDC_CLK_IN_RATE(24000000),
            .SYS_CLK_IN_RATE(25000000),
            .PIXEL_CLK_RATE(pixel_freq),
            .SHIFT_CLK_RATE(pixel_freq*5),
            .SYS_CLK_RATE(CLK_RATE)
            ) CLKS (
                    .sys_clk_in(clk_25mhz),
                    .vidc_clk_in(vidc_ckin),

                    .pixel_clk(clk_pixel),
                    .shift_clk(clk_shift),
                    .sys_clk(clk)
               );

   wire 		   reset;
   reg [1:0]               resetc; // assume start at 0?
   initial begin
`ifdef SIM
           resetc 	<= 0;
`endif
   end
   always @(posedge clk) begin
           if (resetc != 2'b11)
             resetc <= resetc + 1;
   end
   assign 	reset = resetc[1:0] != 2'b11;


   ////////////////////////////////////////////////////////////////////////////////
   /* CPU subsystem:
    * This can be replaced by an SPI module receiving requests from the outside
    * world (e.g. run the firmware on an external MCU).
    */

   wire                    iomem_valid;
   wire [3:0]              iomem_wstrb;
   wire [31:0]             iomem_addr;
   wire [31:0]             iomem_wdata;
   wire [31:0]             iomem_rdata;

   picosocme	#(
                  .BARREL_SHIFTER(1),
                  .ENABLE_MULDIV(1),
                  .ENABLE_COMPRESSED(1),
                  .ENABLE_COUNTERS(0),
                  .ENABLE_IRQ_QREGS(1),

                  .MEM_WORDS(`MEM_SIZE/4),
                  .PROGADDR_RESET(32'h10),
                  .RAM_INIT_FILE("firmware/firmware.hex"),
                  .CLK_RATE(CLK_RATE),
                  .BAUD_RATE(BAUD_RATE)
                  )
                PSM
                  (.clk(clk),
                   .resetn(~reset),

                   .iomem_valid(iomem_valid),
                   .iomem_ready(1'b1),
                   .iomem_wstrb(iomem_wstrb),
                   .iomem_addr(iomem_addr),
                   .iomem_wdata(iomem_wdata),
                   .iomem_rdata(iomem_rdata),

                   .irq_5(1'b0),
                   .irq_6(1'b0),
                   .irq_7(1'b0),

                   .ser_tx(ser_tx),
                   .ser_rx(ser_rx)
                   );


   /* IO starts at 0x20000000:
    * - VIDC regs at 0x20000000
    * - CG mem at    0x21000000
    * - Video regs   0x22000000
    *
    * Peripheral select strobes:
    */
   wire                    vidc_reg_select  = iomem_valid && (iomem_addr[27:24] == 4'h0);
   wire                    cgmem_select     = iomem_valid && (iomem_addr[27:24] == 4'h1);
   wire                    video_reg_select = iomem_valid && (iomem_addr[27:24] == 4'h2);


   ////////////////////////////////////////////////////////////////////////////////
   // VIDC capture

   wire       		conf_hires;	// Configured later, used here

   wire [(12*16)-1:0] 	vidc_palette;
   wire [(12*3)-1:0] 	vidc_cursor_palette;
   wire [10:0]        	vidc_cursor_hstart;
   wire [9:0]         	vidc_cursor_vstart;
   wire [9:0]         	vidc_cursor_vend;
   wire [(24*64)-1:0]   vidc_regs;
   wire [3:0] 		fr_cnt;
   wire [15:0] 		v_dma_ctr;
   wire [15:0] 		c_dma_ctr;
   wire                 vidc_special_written;
   wire [23:0]          vidc_special;
   wire [23:0]          vidc_special_data;
   wire                 load_dma;
   wire                 load_dma_cursor;
   wire [31:0]          load_dma_data;

   wire [5:0]           vidc_reg_idx = iomem_addr[7:2];
   wire [23:0]          vidc_reg_rdata;
   reg [31:0]           vidc_rd; // wire

   wire                 vidc_tregs_status;
   wire                 vidc_tregs_ack;

   vidc_capture	VIDCC(.clk(clk),
                      .reset(reset),

                      // VIDC pins input
                      .vidc_d(vidc_d),
                      .vidc_nvidw(vidc_nvidw),
                      .vidc_nvcs(vidc_nvcs),
                      .vidc_nhs(vidc_nhs),
                      .vidc_nsndrq(vidc_nsndrq),
                      .vidc_nvidrq(vidc_nvidrq),
                      .vidc_flybk(vidc_flybk),
                      .vidc_nsndak(vidc_nsndak),
                      .vidc_nvidak(vidc_nvidak),

                      .conf_hires(conf_hires),

                      .vidc_palette(vidc_palette),
                      .vidc_cursor_palette(vidc_cursor_palette),
                      .vidc_cursor_hstart(vidc_cursor_hstart),
                      .vidc_cursor_vstart(vidc_cursor_vstart),
                      .vidc_cursor_vend(vidc_cursor_vend),

                      .vidc_reg_sel(vidc_reg_idx),
                      .vidc_reg_rdata(vidc_reg_rdata),

                      .tregs_status(vidc_tregs_status),
                      .tregs_status_ack(vidc_tregs_ack),

                      .fr_count(fr_cnt),
                      .video_dma_counter(v_dma_ctr),
                      .cursor_dma_counter(c_dma_ctr),

                      .vidc_special_written(vidc_special_written),
                      .vidc_special(vidc_special),
                      .vidc_special_data(vidc_special_data),

                      .load_dma(load_dma),
                      .load_dma_cursor(load_dma_cursor),
                      .load_dma_data(load_dma_data)
                      );

   // Register read:
   always @(*) begin
           case (iomem_addr[8:2])
             7'b1_0000_00:	vidc_rd = {16'h0, v_dma_ctr};
             7'b1_0000_01:	vidc_rd = {16'h0, c_dma_ctr};
             default:		vidc_rd = {8'h0, vidc_reg_rdata};
           endcase // case (iomem_addr[8:2])
   end

   // LED blinky from frame counter:
   assign led = fr_cnt[3];


   /////////////////////////////////////////////////////////////////////////////
   // Video output control regs, timing/pixel generator:

   wire [31:0] 		   video_reg_rd;
   wire                    v_vsync, v_hsync, v_blank;
   wire [7:0]              v_red;
   wire [7:0]              v_green;
   wire [7:0]              v_blue;

   video VIDEO(.clk(clk),
               .reset(reset),

               .reg_wdata(iomem_wdata),
               .reg_rdata(video_reg_rd),
               .reg_addr(iomem_addr[5:0]),
               .reg_wstrobe(video_reg_select && iomem_wstrb),

               .load_dma(load_dma),
               .load_dma_cursor(load_dma_cursor),
               .load_dma_data(load_dma_data),

               .v_cursor_x(vidc_cursor_hstart),
               .v_cursor_y(vidc_cursor_vstart),
               .v_cursor_yend(vidc_cursor_vend),

               .vidc_palette(vidc_palette),
               .vidc_cursor_palette(vidc_cursor_palette),

               .vidc_special_written(vidc_special_written),
               .vidc_special(vidc_special),
               .vidc_special_data(vidc_special_data),

               .vidc_tregs_status(vidc_tregs_status),
               .vidc_tregs_ack(vidc_tregs_ack),

               .clk_shift(clk_shift),
               .clk_pixel(clk_pixel),

               .video_r(v_red),
               .video_g(v_green),
               .video_b(v_blue),
               .video_hsync(v_hsync),
               .video_vsync(v_vsync),
               .video_blank(v_blank),

               .enable_test_card(sw[0]),

               .sync_flybk(vidc_flybk),

               .is_hires(conf_hires)
               );


   ////////////////////////////////////////////////////////////////////////////////
   // Video output

   /* For testing, this uses Mike Field's vga2dvid module (encodes TMDS, uses DDR
    * regs to output DVI).
    *
    * In future, this will likely drive an external HDMI encoder by exporting
    * parallel RGB video.
    */

`ifndef SIM
   // VGA to digital video converter
   wire [1:0]    tmds[3:0];
   vga2dvid #(
              .c_ddr(1'b1),
              .c_shift_clock_synchronizer(1'b1)
              )
            vga2dvid_instance
              (
               .clk_pixel(clk_pixel),
               .clk_shift(clk_shift),

               .in_red(v_red),
               .in_green(v_green),
               .in_blue(v_blue),
               .in_hsync(v_hsync),
               .in_vsync(v_vsync),
               .in_blank(v_blank),

               .out_clock(tmds[3]),
               .out_red(tmds[2]),
               .out_green(tmds[1]),
               .out_blue(tmds[0])
               );

   // From the ULX3S DVI examples, by EMARD:

   // vendor specific DDR modules
   // convert SDR 2-bit input to DDR clocked 1-bit output (single-ended)
   // onboard GPDI
   ODDRX1F ddr0_clock (.D0(tmds[3][0]), .D1(tmds[3][1]),
                       .Q(gpdi_dp[3]), .SCLK(clk_shift), .RST(0));
   ODDRX1F ddr0_red   (.D0(tmds[2][0]), .D1(tmds[2][1]),
                       .Q(gpdi_dp[2]), .SCLK(clk_shift), .RST(0));
   ODDRX1F ddr0_green (.D0(tmds[1][0]), .D1(tmds[1][1]),
                       .Q(gpdi_dp[1]), .SCLK(clk_shift), .RST(0));
   ODDRX1F ddr0_blue  (.D0(tmds[0][0]), .D1(tmds[0][1]),
                       .Q(gpdi_dp[0]), .SCLK(clk_shift), .RST(0));
`endif


   ////////////////////////////////////////////////////////////////////////////////
   // Finally, combine peripheral read data back to the MCU:

   assign iomem_rdata = vidc_reg_select ? vidc_rd :
                        cgmem_select ? 32'hffffffff :
                        video_reg_select ? video_reg_rd :
                        32'h0;

endmodule // soc_top
