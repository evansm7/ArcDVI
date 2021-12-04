/* Instantiates soc_top, giving it clock.
 * This test harness is extremely basic, and should eventually model VIDC, capture
 * output, perform register interactions etc.
 *
 * 27/5/20 ME
 * Includes a portion from picorv32/picosoc/icebreaker_tb.v, which is
 * copyright 2017 Claire Wolf.
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


module tb_top();

   reg 			clk;
   reg 			reset;
   wire                 ser_tx;

   always #`CLK_P       clk <= ~clk;

   ////////////////////////////////////////////////////////////////////////////////

   // Note, no reset
   soc_top #( .CLK_RATE(25000000),
              .BAUD_RATE(2500000)
             ) DUT (
                    .clk_25mhz(clk),
                    .btn(1'b0),

                    .ser_rx(1'b1),
                    .ser_tx(ser_tx)
	            );

   ////////////////////////////////////////////////////////////////////////////////

   reg 			junk;

   initial begin
      if (!$value$plusargs("NO_VCD=%d", junk)) begin
         $dumpfile("tb_top.vcd");
         $dumpvars(0, tb_top);
      end

      clk   <= 1;
      reset <= 1;
      #(`CLK*2);
      reset <= 0;

      $display("Starting sim");
      #(`CLK*100000);

      $display("Done.");
      $finish;
   end


   /* From picosoc/icebreaker_tb.v: */
   reg [7:0] buffer;
   localparam ser_half_period = 10/2; // CLK/BAUD/2
   event     ser_sample;

   always begin
           @(negedge ser_tx);

           repeat (ser_half_period) @(posedge clk);
           -> ser_sample; // start bit

           repeat (8) begin
                   repeat (ser_half_period) @(posedge clk);
                   repeat (ser_half_period) @(posedge clk);
                   buffer = {ser_tx, buffer[7:1]};
                   -> ser_sample; // data bit
           end

           repeat (ser_half_period) @(posedge clk);
           repeat (ser_half_period) @(posedge clk);
           -> ser_sample; // stop bit

           if (buffer < 32 || buffer >= 127)
             $display("[%d]", buffer);
           else
             $write("%c", buffer);
   end

endmodule
