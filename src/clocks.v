/* ArcDVI clock generation
 *
 * Generate clocks for video and system from input crystal/VIDC clocks.
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

module clocks(input wire  sys_clk_in,
              input wire  vidc_clk_in,
              output wire pixel_clk,
              output wire shift_clk,
              output wire sys_clk
              );

   parameter VIDC_CLK_IN_RATE = 0;
   parameter SYS_CLK_IN_RATE = 0;

   parameter PIXEL_CLK_RATE = 0;
   parameter SHIFT_CLK_RATE = 0;
   parameter SYS_CLK_RATE = 0;

   wire [3:0]   clocksS;
   wire       	clk_lockedS;
   wire [3:0]   clocksP;
   wire       	clk_lockedP;
   assign       sys_clk = clocksS[0];
   assign       pixel_clk = clocksP[0];
   assign       shift_clk = clocksP[1];

`ifndef SIM

 `define ORIG_PLL_STUFF

 `ifdef ORIG_PLL_STUFF
   ecp5pll
     #(
       .in_hz(SYS_CLK_IN_RATE),
       .out0_hz(SYS_CLK_RATE)
       )
   ecp5pll_sys
     (
      .clk_i(sys_clk_in),
      .clk_o(clocksS),
      .locked(clk_lockedS)
      );

   ecp5pll
     #(
       .in_hz(VIDC_CLK_IN_RATE),
       .out0_hz(PIXEL_CLK_RATE),
       .out1_hz(SHIFT_CLK_RATE)
       )
   ecp5pll_pix
     (
      .clk_i(vidc_clk_in),
      .clk_o(clocksP),
      .locked(clk_lockedP)
      );

 `else

   /* Instantiate the PLLs manually, with (in theory) the same parameters as above,
    * in an attempt to get Diamond to do something smart.
    */
   (* FREQUENCY_PIN_CLKI="024.000000" *)
   (* FREQUENCY_PIN_CLKOP="084.000000" *)
   (* FREQUENCY_PIN_CLKOS="390.000000" *)
   // res 16 current 13
  (* ICP_CURRENT="13" *) (* LPF_RESISTOR="16" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
  EHXPLLL
  #(
    .CLKI_DIV     (4),
    .CLKFB_DIV    (13),
    .FEEDBK_PATH  ("CLKOP"),

    .OUTDIVIDER_MUXA("DIVA"),
    .CLKOP_ENABLE ("ENABLED"),
    .CLKOP_DIV    (10),
    .CLKOP_CPHASE (9),
    .CLKOP_FPHASE (0),

    .OUTDIVIDER_MUXB("DIVB"),
    .CLKOS_ENABLE ("ENABLED"),
    .CLKOS_DIV    (2),
    .CLKOS_CPHASE (1),
    .CLKOS_FPHASE (0),

    .OUTDIVIDER_MUXC("DIVC"),
    .CLKOS2_ENABLE("DISABLED"),
    .CLKOS2_DIV   (1),
    .CLKOS2_CPHASE(0),
    .CLKOS2_FPHASE(0),

    .OUTDIVIDER_MUXD("DIVD"),
    .CLKOS3_ENABLE("DISABLED"),
    .CLKOS3_DIV   (1),
    .CLKOS3_CPHASE(0),
    .CLKOS3_FPHASE(0),

    .INTFB_WAKE   ("DISABLED"),
    .STDBY_ENABLE ("DISABLED"),
    .PLLRST_ENA   ("DISABLED"),
    .DPHASE_SOURCE("DISABLED"),
    .PLL_LOCK_MODE(0)
  )
  pll_instP
  (
    .RST(1'b0),
    .STDBY(1'b0),
    .CLKI(vidc_clk_in),
    .CLKOP (clocksP[0]),
    .CLKOS (clocksP[1]),
    .CLKOS2(clocksP[2]),
    .CLKOS3(clocksP[3]),
    .CLKFB(clocksP[0]),
    .CLKINTFB(),
    .PHASESEL1(1'b0),
    .PHASESEL0(1'b0),
    .PHASEDIR(1'b0),
    .PHASESTEP(1'b0),
    .PHASELOADREG(1'b0),
    .PLLWAKESYNC(1'b0),
    .ENCLKOP(1'b0),
    .ENCLKOS(1'b0),
    .ENCLKOS2(1'b0),
    .ENCLKOS3(1'b0),
    .LOCK(clk_lockedP)
  );



   (* FREQUENCY_PIN_CLKI="025.000000" *)
   (* FREQUENCY_PIN_CLKOP="050.000000" *)
   // res 16 current 13
  (* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
  EHXPLLL
  #(
    .CLKI_DIV     (1),
    .CLKFB_DIV    (2),
    .FEEDBK_PATH  ("CLKOP"),

    .OUTDIVIDER_MUXA("DIVA"),
    .CLKOP_ENABLE ("ENABLED"),
    .CLKOP_DIV    (12),
    .CLKOP_CPHASE (11),
    .CLKOP_FPHASE (0),

    .OUTDIVIDER_MUXB("DIVB"),
    .CLKOS_ENABLE ("DISABLED"),
    .CLKOS_DIV    (1),
    .CLKOS_CPHASE (0),
    .CLKOS_FPHASE (0),

    .OUTDIVIDER_MUXC("DIVC"),
    .CLKOS2_ENABLE("DISABLED"),
    .CLKOS2_DIV   (1),
    .CLKOS2_CPHASE(0),
    .CLKOS2_FPHASE(0),

    .OUTDIVIDER_MUXD("DIVD"),
    .CLKOS3_ENABLE("DISABLED"),
    .CLKOS3_DIV   (1),
    .CLKOS3_CPHASE(0),
    .CLKOS3_FPHASE(0),

    .INTFB_WAKE   ("DISABLED"),
    .STDBY_ENABLE ("DISABLED"),
    .PLLRST_ENA   ("DISABLED"),
    .DPHASE_SOURCE("DISABLED"),
    .PLL_LOCK_MODE(0)
  )
  pll_instS
  (
    .RST(1'b0),
    .STDBY(1'b0),
    .CLKI(sys_clk_in),
    .CLKOP (clocksS[0]),
    .CLKOS (clocksS[1]),
    .CLKOS2(clocksS[2]),
    .CLKOS3(clocksS[3]),
    .CLKFB(clocksS[0]),
    .CLKINTFB(),
    .PHASESEL1(1'b0),
    .PHASESEL0(1'b0),
    .PHASEDIR(1'b0),
    .PHASESTEP(1'b0),
    .PHASELOADREG(1'b0),
    .PLLWAKESYNC(1'b0),
    .ENCLKOP(1'b0),
    .ENCLKOS(1'b0),
    .ENCLKOS2(1'b0),
    .ENCLKOS3(1'b0),
    .LOCK(clk_lockedS)
  );

 `endif

`else // !`ifndef SIM
   assign clocksS[0] = sys_clk_in;
   assign clocksP[0] = vidc_clk_in;
   assign clocksP[1] = vidc_clk_in; // FIXME
`endif // !`ifndef SIM

endmodule // clocks
