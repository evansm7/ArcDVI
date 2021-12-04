/* Instantiates video_timing, giving it CLK/reset.
 *
 * 27/5/20 ME
 *
 * Copyright 2020, 2021 Matt Evans
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

`define CLK   	40
`define CLK_P 	(`CLK/2)
`define SIM 	1


module tb_comp_video_timing();

   reg 			 clk;
   reg 			 reset;
   reg                   flybk;
   reg                   csr;
   wire                  csa;

   always #`CLK_P       clk <= ~clk;

   ////////////////////////////////////////////////////////////////////////////////

   wire [7:0]            pr;
   wire [7:0]            pg;
   wire [7:0]            pb;
   wire                  hs, vs, de;
   reg                   load_dma;

`define C_RES_X 1152
`define C_HFP 40
`define C_HSW 20
`define C_HBP 62
`define C_RES_Y 896
`define C_VFP 4
`define C_VSW 3
`define C_VBP 47

   // Note, no reset
   video_timing #(
                  ) DUT (
                         .pclk(clk),

                         .t_horiz_res(`C_RES_X),
                         .t_horiz_fp(`C_HFP),
                         .t_horiz_sync_width(`C_HSW),
                         .t_horiz_bp(`C_HBP),

                         .t_vert_res(`C_RES_Y),
                         .t_vert_fp(`C_VFP),
                         .t_vert_sync_width(`C_VSW),
                         .t_vert_bp(`C_VBP),

                         .t_words_per_line_m1(8'd35),
                         .t_bpp(2'd3),
                         .t_hires(1'b1),
                         .t_double_x(1'b0),
                         .t_double_y(1'b0),

                         .v_cursor_x(11'h69),
                         .v_cursor_y(10'h123),
                         .v_cursor_yend(10'h143),

                         .o_r(pr),
                         .o_g(pg),
                         .o_b(pb),
                         .o_hsync(hs),
                         .o_vsync(vs),
                         .o_de(de),

                         .load_dma_clk(clk),
                         .load_dma(load_dma),
                         .load_dma_data(32'hfeedface),

                         .sync_flyback(flybk),

                         .config_sync_req(csr),
                         .config_sync_ack(csa),

                         .enable_test_card(1'b1)
	                 );

   ////////////////////////////////////////////////////////////////////////////////

   reg 			junk;

   initial begin
           if (!$value$plusargs("NO_VCD=%d", junk)) begin
                   $dumpfile("tb_comp_video_timing.vcd");
                   $dumpvars(0, tb_comp_video_timing);
           end
           clk   <= 1;
           load_dma <= 0;
           flybk <= 1;
           csr   <= 0;

           reset <= 1;
           #(`CLK*2);
           reset <= 0;

           #(`CLK*10);

           csr <= 1;

           // Drop flyback, and wait for dut to sync to it:
           #(`CLK*70);
           flybk <= 0;

           @(posedge csa);
           @(posedge clk);

           // Now run a few clocks:
           #(`CLK*3000000);
           $finish;
   end

endmodule
