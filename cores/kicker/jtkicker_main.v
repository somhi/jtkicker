/*  This file is part of JTKICKER.
    JTKICKER program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTKICKER program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTKICKER.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 11-11-2021 */

module jtkicker_main(
    input               rst,
    input               clk,        // 24 MHz
    input               cpu4_cen,   // 6 MHz
    output              cpu_cen,    // Q clock
    input               ti1_cen,
    input               ti2_cen,
    // ROM
    output reg  [16:0]  rom_addr,
    output reg          rom_cs,
    input       [ 7:0]  rom_data,
    input               rom_ok,
    // cabinet I/O
    input       [ 1:0]  start_button,
    input       [ 1:0]  coin_input,
    input       [ 5:0]  joystick1,
    input       [ 5:0]  joystick2,
    input               service,

    // GFX
    output      [10:0]  vram_addr,
    output      [10:0]  obj_addr,
    output              cpu_rnw,
    output      [ 7:0]  cpu_dout,
    output      [ 2:0]  pal_sel,
    input               LVBL,
    input               V16,
    output reg          gfx_cs,
    output reg          flip,

    input      [7:0]    vram_dout,
    input      [7:0]    oram_dout,
    // DIP switches
    input               dip_pause,
    input      [7:0]    dipsw_a,
    input      [7:0]    dipsw_b,
    input      [3:0]    dipsw_c,

    // Sound
    output signed [15:0] snd,
    output               sample,
    output               peak
);

wire [ 7:0] prot_dout, ram_dout;
wire [15:0] A;
wire        RnW, irq_n, irq_ack;
wire        irq_trigger;
reg         nmi_clrn, irq_clrn;
wire        VMA;

assign irq_trigger = ~gfx_irqn & dip_pause;
assign cpu_rnw     = RnW;
assign vram_addr    = A[10:0];
assign obj_addr    = { A[11], A[9:0] };
assign sample      = 0;

always @(*) begin
    rom_cs  = A[15:14] !=0 && RnW && VMA; // ROM = 4000 - FFFF
    case( A[13:11] )
        0: case(A[10:8] )
            0: iow_cs = 1;
            1: afe_cs = 1;  // watchdog
            2: intshow_cs = 1; // related to VSCR
            3: ti2_cs   = 1; // TITG2 in sch.
            4: ti1_cs   = 1; // TITG1 in sch.
            5: dip2_cs  = 1;
            6: dip3_cs  = 1;
            7: ior_cs   = 1; // IOEN in sch.
        endcase
        1: tidata2_cs = 1;
        2: tidata1_cs = 1;
        3: color_cs = 1;
        4: vscr_cs  = 1;
        5,6: obj_cs = 1;
        7: vram_cs  = 1;
    endcase
end


always @(posedge clk) begin
    case( A[1:0] )
        0: cabinet <= { 4'hf, dipsw_c };
        1: cabinet <= {2'b11, joystick2[5:4], joystick2[2], joystick2[3], joystick2[0], joystick2[1]};
        2: cabinet <= {2'b11, joystick1[5:4], joystick1[2], joystick1[3], joystick1[0], joystick1[1]};
        3: cabinet <= { ~3'd0, start_button, service, coin_input };
    endcase
    cpu_din <= rom_cs  ? rom_data  :
               vram_cs ? ram_dout  :
               gfx_cs  ? gfx_dout  :
               in_cs   ? cabinet   :
               sys_cs  ? sys_dout  : 8'hff;
end

always @(posedge clk) begin
    if( rst ) begin
        nmi_clrn <= 0;
        irq_clrn <= 0;
        flip     <= 0;
        pal_sel  <= 0;
    end else if(cpu_cen) begin
        if( iow_cs ) begin
            nmi_clrn <= cpu_dout[1];
            irq_clrn <= cpu_dout[2];
            flip     <= cpu_dout[0];
        end
        if( color_cs ) pal_sel <= cpu_dout[2:0];
        if( vscr_cs  ) vpos <= cpu_dout;
    end
end

jtframe_cen3p57 #(.CLK24(1)) u_cen(
    .clk        ( clk       ),
    .cen_3p57   ( cen_fm    ),
    .cen_1p78   (           )
);

jtframe_ff u_ff(
    .clk      ( clk         ),
    .rst      ( rst         ),
    .cen      ( 1'b1        ),
    .din      ( 1'b1        ),
    .q        (             ),
    .qn       ( irq_n       ),
    .set      (             ),    // active high
    .clr      ( ~irq_clrn   ),    // active high
    .sigedge  ( irq_trigger )     // signal whose edge will trigger the FF
);

reg  [ 7:0] ti1_data, ti2_data;
wire [10:0] ti1_snd,  ti2_snd;
wire        rdy1, rdy2;

always @(posedge clk, posedge rst) begin
    if( rst ) begin
        ti1_data <= 0;
        ti_data2 <= 0;
    end else begin
        if( tidata1_cs ) ti1_data <= cpu_dout;
        if( tidata2_cs ) ti_data2 <= cpu_dout;
    end
end

jt89 u_ti1(
    .rst    ( rst           ),
    .clk    ( clk           ),
    .clk_en ( ti1_cen       ),
    .wr_n   ( rdy1 & ~ti1_cs),
    .ce_n   ( ~ti1_cs       ),
    .din    ( ti1_data      ),
    .sound  ( ti1_snd       ),
    .ready  ( rdy1          )
);

jt89 u_ti2(
    .rst    ( rst           ),
    .clk    ( clk           ),
    .clk_en ( ti2_cen       ),
    .wr_n   ( rdy2 & ~ti2_cs),
    .ce_n   ( ~ti2_cs       ),
    .din    ( ti2_data      ),
    .sound  ( ti2_snd       ),
    .ready  ( rdy2          )
);

jtframe_sys6809 #(.RAM_AW(0)) u_cpu(
    .rstn       ( ~rst      ),
    .clk        ( clk       ),
    .cen        ( cen12     ),   // This is normally the input clock to the CPU
    .cpu_cen    ( cpu_cen   ),   // 1/4th of cen -> 3MHz

    // Interrupts
    .nIRQ       ( irq_n     ),
    .nFIRQ      ( nmi_n     ),
    .nNMI       ( 1'b1      ),
    .irq_ack    (           ),
    // Bus sharing
    .bus_busy   ( 1'b0      ),
    .waitn      (           ),
    // memory interface
    .A          ( A         ),
    .RnW        ( RnW       ),
    .VMA        ( VMA       ),
    .ram_cs     ( 1'b0      ),
    .rom_cs     ( rom_cs    ),
    .rom_ok     ( rom_ok    ),
    // Bus multiplexer is external
    .ram_dout   (           ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_din    ( cpu_din   )
);


jtframe_mixer #(.W0(10),.W1(10)) u_mixer(
    .rst    ( rst       ),
    .clk    ( clk       ),
    .cen    ( cen_ti1   ),
    // input signals
    .ch0    ( ti1_snd   ),
    .ch1    ( ti2_snd   ),
    .ch2    (           ),
    .ch3    (           ),
    // gain for each channel in 4.4 fixed point format
    .gain0  ( 8'h08     ),
    .gain1  ( 8'h08     ),
    .gain2  ( 8'h00     ),
    .gain3  ( 8'h00     ),
    .mixed  ( snd       ),
    .peak   ( peak      )
);

endmodule
