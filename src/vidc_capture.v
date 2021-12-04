/* Capture VIDC registers, DMA and interesting configuration observations.
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

module vidc_capture(input wire 	       	      clk,
                    input wire                reset,

                    /* VIDC signals directly from pins: */
                    input wire [31:0]         vidc_d,
                    input wire                vidc_nvidw,
                    input wire                vidc_nvcs,
                    input wire                vidc_nhs,
                    input wire                vidc_nsndrq, // Unused
                    input wire                vidc_nvidrq,
                    input wire                vidc_flybk,
                    input wire                vidc_nsndak, // Unused
                    input wire                vidc_nvidak,

                    /* Input config */
                    input wire                conf_hires,

                    /* Output info: */
                    output wire [(12*16)-1:0] vidc_palette,
                    output wire [(12*3)-1:0]  vidc_cursor_palette,
                    output wire [10:0]        vidc_cursor_hstart,
                    output wire [9:0]         vidc_cursor_vstart,
                    output wire [9:0]         vidc_cursor_vend,

                    input wire [5:0]          vidc_reg_sel,
                    output wire [23:0]        vidc_reg_rdata,

                    output reg                tregs_status,
                    input wire                tregs_status_ack,

                    /* Debug counters: */
                    output reg [3:0]          fr_count,
                    output reg [15:0]         video_dma_counter,
                    output reg [15:0]         cursor_dma_counter,

                    /* Extension register interface: */
                    output reg                vidc_special_written,
                    output wire [23:0]        vidc_special,
                    output wire [23:0]        vidc_special_data,

                    /* DMA interface: */
                    output wire               load_dma,
                    output wire               load_dma_cursor,
                    output wire [31:0]        load_dma_data
                    );


   /* Principle of operation:
    *
    * The VIDC is clocked at 24MHz, but the register writes (strobed by /VIDW)
    * aren't necessarily synchronous to this.  We treat the strobe (and DMA
    * strobes from MEMC) as fully asynchronous, and synchronise them on input.
    *
    * A register write is then detected by the rising edge of /VIDW; the data
    * comes from a pipeline that gives the data sampled when /VIDW was still low.
    *
    * The DMA works the same, though the timing is tighter; the data comes from
    * a 1 stage deeper pipeline, i.e. "further back in time".
    */

   /* These registers mirror the VIDC registers (64 words of).
    *
    * Our special "port" register is at register offset 0x50/51
    * (i.e. reg 0x14/0x15).
    * VIDC decodes this, harmlessly, to the border reg & cursor col1 reg.
    */
   reg [23:0]           vidc_regs[63:0];

   assign vidc_reg_rdata 	= vidc_regs[vidc_reg_sel][23:0];


   ////////////////////////////////////////////////////////////////////////////////
   // Data bus capture, synchronisers and pipeline/history bit:
   reg                  vidc_nvidw_hist[2:0];
   reg [31:0]           vidc_d_hist[2:0];

   wire                 nvidw_edge          = (vidc_nvidw_hist[2] == 1) &&
                        (vidc_nvidw_hist[1] == 0);

   wire	[5:0]		vidc_reg_addr       = vidc_d_hist[1][31:26];

   /* Detect changes to display timing:
    * This isn't foolproof, testing only HCR/VCR, but is enough to detect a
    * standard OS-driven mode change.
    */
   wire                 tregs               = (vidc_reg_addr == 8'h80/4) ||
                        (vidc_reg_addr == 8'ha0/4);

   always @(posedge clk) begin
           if (reset) begin
                   tregs_status       	<= 1'b0;
                   vidc_nvidw_hist[0]   <= 1'b0;
                   vidc_nvidw_hist[1]   <= 1'b0;
                   vidc_nvidw_hist[2]   <= 1'b0;
                   vidc_special_written <= 0;

           end else begin
                   // Watch for nVIDW falling edge:
                   vidc_nvidw_hist[0] <= vidc_nvidw;
                   vidc_nvidw_hist[1] <= vidc_nvidw_hist[0];
                   vidc_nvidw_hist[2] <= vidc_nvidw_hist[1];

                   // Synchroniser/delay on D to align with sampled edge:
                   vidc_d_hist[0] <= vidc_d;
                   vidc_d_hist[1] <= vidc_d_hist[0];
                   vidc_d_hist[2] <= vidc_d_hist[1];

                   if (nvidw_edge) begin
                           /* vidc_d_hist[1] is data sampled at same point as the
                            * strobe which has been detected as being low.
                            */
                           vidc_regs[vidc_reg_addr] <= vidc_d_hist[1][23:0];
                           vidc_special_written     <= (vidc_reg_addr == 6'h14);

                           if (tregs && (tregs_status_ack == tregs_status))
                             tregs_status <= ~tregs_status;
                   end else begin
                           vidc_special_written <= 0;
                   end
           end
   end


   ////////////////////////////////////////////////////////////////////////////////
   // Registers to export directly to display circuitry:

   assign vidc_cursor_hstart         	= conf_hires ? vidc_regs[6'h26][21:11] :
                                          vidc_regs[6'h26][23:13];
   wire [9:0] vidc_vstart    		= vidc_regs[6'h2b][23:14];
   assign vidc_cursor_vstart 		= vidc_regs[6'h2e][23:14] - vidc_vstart;
   assign vidc_cursor_vend 		= vidc_regs[6'h2f][23:14] - vidc_vstart;

   assign vidc_palette  		= { vidc_regs[15][11:0], vidc_regs[14][11:0],
                                            vidc_regs[13][11:0], vidc_regs[12][11:0],
                                            vidc_regs[11][11:0], vidc_regs[10][11:0],
                                            vidc_regs[9][11:0], vidc_regs[8][11:0],
                                            vidc_regs[7][11:0], vidc_regs[6][11:0],
                                            vidc_regs[5][11:0], vidc_regs[4][11:0],
                                            vidc_regs[3][11:0], vidc_regs[2][11:0],
                                            vidc_regs[1][11:0], vidc_regs[0][11:0] };

   assign vidc_cursor_palette 		= { vidc_regs[19][11:0], vidc_regs[18][11:0],
                                            vidc_regs[17][11:0] };

   // When vidc_special is changed, vidc_special_written pulses:
   assign        vidc_special	 	= vidc_regs[6'h14];
   assign        vidc_special_data  	= vidc_regs[6'h15];


   ////////////////////////////////////////////////////////////////////////////////
   // Tracking syncs and DMA requests:

   wire			vs, hs, vs_last, hs_last;
   reg [2:0]            s_vs;
   reg [2:0]            s_hs;
   reg [2:0]            s_flybk;
   assign		vs = s_vs[1];	// Watch out!  Might be composite sync
   assign		hs = s_hs[1];
   assign		vs_last = s_vs[2];
   assign		hs_last = s_hs[2];
   wire                 flybk = s_flybk[1];
   wire                 flybk_last = s_flybk[2];

   wire			vdrq, vdak, vdrq_last, vdak_last;
   reg [2:0]	        s_vdrq;
   reg [2:0]	        s_vdak;
   assign		vdrq             = s_vdrq[1];
   assign		vdrq_last 	 = s_vdrq[2];
   assign		vdak             = s_vdak[1];
   assign		vdak_last 	 = s_vdak[2];
   wire			new_video_dmarq  = (vdrq == 0) && (hs == 1);
   wire			new_cursor_dmarq = (vdrq == 0) && (hs == 0);

   reg [15:0]           int_v_dma_counter;
   reg [15:0]           int_c_dma_counter;
   reg [2:0]            dma_beat_counter;
   reg [1:0]            v_state;

   wire                 flybk_start      = ~flybk_last && flybk;
   wire                 vdak_rising_edge = vdak_last == 0 && vdak == 1;
   wire                 hs_rising_edge   = hs_last == 0 && hs == 1;

   always @(posedge clk) begin
           if (reset) begin
                   v_state  <= 0;
                   s_vs     <= 3'b111;
                   s_hs     <= 3'b111;
                   s_flybk  <= 3'b111;
                   s_vdrq   <= 3'b111;
                   s_vdak   <= 3'b111;
                   fr_count <= 0;
           end else begin

                   // Synchronisers & history/edge-detect:
                   s_vs[2:0]    <= {s_vs[1:0], vidc_nvcs};
                   s_hs[2:0]    <= {s_hs[1:0], vidc_nhs};
                   s_flybk[2:0] <= {s_flybk[1:0], vidc_flybk};

                   s_vdrq[2:0]  <= {s_vdrq[1:0], vidc_nvidrq};
                   s_vdak[2:0]  <= {s_vdak[1:0], vidc_nvidak};

                   if (flybk_start) begin
                           // reset counters at start of flyback
                           video_dma_counter  <= int_v_dma_counter;
                           int_v_dma_counter  <= 0;
                           cursor_dma_counter <= int_c_dma_counter;
                           int_c_dma_counter  <= 0;

                           // Useful for LED blinky, and wait-for-next-frame:
                           fr_count           <= fr_count + 1;
                   end

                   /* Note, it can happen that a DMA ack occurs coincident with
                    * the start of flyback... so a counter could be incremented
                    * after all.
                    *
                    * This FSM relies on MEMC always returning four beats (as
                    * it should).
                    */
                   if (v_state == 0) begin // Idle
                           if (new_video_dmarq) begin
                                   v_state           <= 1;
                                   int_v_dma_counter <= int_v_dma_counter + 1;
                                   dma_beat_counter  <= 3;
                           end else if (new_cursor_dmarq) begin
                                   v_state           <= 2;
                                   int_c_dma_counter <= int_c_dma_counter + 1;
                                   dma_beat_counter  <= 3;
                           end
                   end else begin // Some kind of DMA ongoing
                           // Look for a rising edge on vidak:
                           if (vdak_rising_edge) begin
                                   // FIXME, poke vidc_d_hist[1] into FIFO
                                   if (dma_beat_counter != 0) begin
                                           dma_beat_counter <= dma_beat_counter - 1;
                                   end else begin
                                           // Seen 'em all.
                                           v_state <= 0;
                                   end
                           end
                   end
           end
   end // always @ (posedge clk)

   // Now we know when DMA is being transferred, and have the data:
   assign load_dma              = !reset && (v_state == 1) && vdak_rising_edge;
   assign load_dma_cursor       = !reset && (v_state == 2) && vdak_rising_edge;
   assign load_dma_data 	= vidc_d_hist[2];

endmodule // vidc_capture
