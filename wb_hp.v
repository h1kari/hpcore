`default_nettype none

//`define USE_POWER_PINS 1
`define IO_INPUT  1'b1
`define IO_OUTPUT 1'b0
`define SET_IO_OUTPUT(sig, pin) \
    assign gpio_enb[pin] = {16{`IO_OUTPUT}}; \
    assign gpio_o[pin] = sig
`define SET_IO_INPUT(sig, pin) \
    assign gpio_enb[pin] = {16{`IO_INPUT}}; \
    assign sig = gpio_i[pin] 
`define SET_IO_NA(pin) \
    assign gpio_enb[pin] = {16{`IO_INPUT}}
    
/* gpio/wb settings:
 * 0 - vcc           [I]
 * 1 - Alarm_rst     [I]
 * 2 - Alarm_ctr_rst [I]
 * 3 - Glitch        [I]
 * 4 - Alarm         [O]
 * 5 - Alarm_latch   [O]
 * 6:13 - Alarm_ctr  [O]
 * 15:14 - PN_select [I]
 *
 * design options:
 * 0 - only positive detector
 * 1 - only negative detector
 * 2 - both detectors
 */
 
module hp_glitcher #(
    parameter GLITCH_OFF = 137,
    parameter GLITCH0 = GLITCH_OFF + 3,
    parameter GLITCH1 = GLITCH_OFF + 5,
    parameter GLITCH2 = GLITCH_OFF + 7,
    parameter GLITCH3 = GLITCH_OFF + 11,
    parameter GLITCH4 = GLITCH_OFF + 13,
    parameter GLITCH5 = GLITCH_OFF + 17,
    parameter GLITCH6 = GLITCH_OFF + 19,
    parameter GLITCH7 = GLITCH_OFF + 23
) (
    input  wire clk,
    input  wire reset,
    input  wire enable,
    output wire glitch
);

reg [19:0] counter = 0;
reg glitch_r = 0;
always @(posedge clk)
begin
    glitch_r <= 0;
    if (reset | !enable)
        counter <= 0;
    else if (enable)
    begin
        counter <= counter + 1;
        case(counter)
        GLITCH0: glitch_r <= 1;
        GLITCH1: glitch_r <= 1;
        GLITCH2: glitch_r <= 1;
        GLITCH3: glitch_r <= 1;
        GLITCH4: glitch_r <= 1;
        GLITCH5: glitch_r <= 1;
        GLITCH6: glitch_r <= 1;
        GLITCH7: glitch_r <= 1;
        endcase
    end
end

assign glitch = glitch_r & !clk;

endmodule

module wb_hp #(
    parameter   [1:0]   DESIGN             = 2,
    parameter   [31:0]  BASE_ADDRESS       = 32'h3000_0000,        // base address
    parameter           ENABLE_GLITCH      = 1
) (
`ifdef USE_POWER_PINS
    inout  wire vdda1,	// User area 1 3.3V supply
    inout  wire vdda2,	// User area 2 3.3V supply
    inout  wire vssa1,	// User area 1 analog ground
    inout  wire vssa2,	// User area 2 analog ground
    inout  wire vccd1,	// User area 1 1.8V supply
    inout  wire vccd2,	// User area 2 1.8v supply
    inout  wire vssd1,	// User area 1 digital ground
    inout  wire vssd2,	// User area 2 digital ground
`endif
    input  wire          wb_clk_i,
    input  wire          reset,

    input  wire          user_clock2,

    // wb interface
    input  wire          wbs_cyc_i,       // wishbone transaction
    input  wire          wbs_stb_i,       // strobe - data valid and accepted as long as !wbs_stall_o
    input  wire          wbs_we_i,        // write enable
    input  wire [31:0]   wbs_adr_i,      // address
    input  wire [31:0]   wbs_dat_i,      // incoming data
    output reg           wbs_ack_o,       // request is completed 
    output wire          wbs_stl_o,     // cannot accept req
    output reg  [31:0]   wbs_dat_o,      // output data

    // buttons
    input  wire [15:0]   gpio_i,
    output wire [15:0]   gpio_enb,        // not enable - low for active
    output wire [15:0]   gpio_o,
    
    output wire          glitch
);
       
wire       hp_Alarm;
wire       hp_vcc,    hp_glitch_en;
reg        wb_hp_vcc, wb_hp_glitch_en;
wire [1:0] hp_pn_select;
reg  [1:0] wb_hp_pn_select;

generate
    if (ENABLE_GLITCH)
    begin
        hp_glitcher
        hp_glitcher
        (
            .clk(user_clock2),
            .reset(reset),
            .enable(hp_glitch_en | wb_hp_glitch_en),
            .glitch(glitch)
        );
    end
    else
        assign glitch = 0;
endgenerate

wire hp_Alarm_p, hp_Alarm_n;
hoggephase #(0)
hoggephase_p
(
    .CK(user_clock2),
    .VCC(hp_vcc | wb_hp_vcc),
    .Alarm(hp_Alarm_p),
    .glitch(glitch)
);
hoggephase #(1)
hoggephase_n
(
    .CK(user_clock2),
    .VCC(hp_vcc | wb_hp_vcc),
    .Alarm(hp_Alarm_n),
    .glitch(glitch)
);

// select which detectors to use...
assign hp_Alarm = ((hp_pn_select[0] | wb_hp_pn_select[0]) & hp_Alarm_p) |
                  ((hp_pn_select[1] | wb_hp_pn_select[1]) & hp_Alarm_n);
    
assign wbs_stl_o = 0;

// latch Alarm to catch small glitches
reg  hp_Alarm_latch = 0;
wire hp_Alarm_rst;
reg  wb_hp_Alarm_rst = 0;
wire hp_Alarm_latch_async_rst = hp_Alarm_rst | wb_hp_Alarm_rst | reset;
always @(*) //hp_Alarm_latch_async_rst or hp_Alarm)
begin
    if (hp_Alarm_latch_async_rst)
        hp_Alarm_latch <= 0;
    else if (hp_Alarm)
        hp_Alarm_latch <= 1;
end

// implement counter clocked by alarm signal, this in theory shouldn't be faster than the speed of clk ?
reg  [7:0] hp_Alarm_ctr = 0;
wire hp_Alarm_ctr_rst;
reg  wb_hp_Alarm_ctr_rst = 0;
wire hp_Alarm_ctr_async_rst = hp_Alarm_ctr_rst | wb_hp_Alarm_ctr_rst | reset;
always @(*) //hp_Alarm_ctr_async_rst or hp_Alarm)
begin
    if (hp_Alarm_ctr_async_rst)
        hp_Alarm_ctr <= 0;
    else if (hp_Alarm)
        hp_Alarm_ctr <= hp_Alarm_ctr + 1;
end

// writes
reg [7:0] Alarm_counter = 0;
always @(posedge wb_clk_i)
begin
    if (reset)
    begin
        wb_hp_vcc           <= 0;
        wb_hp_Alarm_rst     <= 0;
        wb_hp_Alarm_ctr_rst <= 0;
        wb_hp_glitch_en     <= 0;
        wb_hp_pn_select     <= 0;
    end
    else if (wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stl_o &&
             wbs_adr_i == BASE_ADDRESS)
    begin
        wb_hp_vcc           <= wbs_dat_i[0];
        wb_hp_Alarm_rst     <= wbs_dat_i[1];
        wb_hp_Alarm_ctr_rst <= wbs_dat_i[2];
        wb_hp_glitch_en     <= wbs_dat_i[3];
        wb_hp_pn_select     <= wbs_dat_i[15:14];
    end
end

// reads
always @(posedge wb_clk_i)
begin
    if (reset)
    begin
        wbs_dat_o <= 32'h0;
    end
    else
    begin
        if (wbs_stb_i && wbs_cyc_i && !wbs_we_i && !wbs_stl_o &&
            wbs_adr_i == BASE_ADDRESS)
        begin
            wbs_dat_o <= {16'h0,
                          wb_hp_pn_select,
                          hp_Alarm_ctr, hp_Alarm_latch, hp_Alarm,
                          wb_hp_glitch_en, wb_hp_Alarm_ctr_rst,
                          wb_hp_Alarm_rst, wb_hp_vcc};
        end
        else
        begin
            wbs_dat_o <= 32'h0;
        end
    end
end

// acks
always @(posedge wb_clk_i)
begin
    if (reset)
        wbs_ack_o <= 0;
    else
        // return ack immediately
        wbs_ack_o <= (wbs_stb_i && !wbs_stl_o && (wbs_adr_i == BASE_ADDRESS));
end

// gpio inputs
`SET_IO_INPUT  (hp_vcc,           0);
`SET_IO_INPUT  (hp_Alarm_rst,     1);
`SET_IO_INPUT  (hp_Alarm_ctr_rst, 2);
`SET_IO_INPUT  (hp_glitch_en,     3);
`SET_IO_INPUT  (hp_pn_select,     15:14);
    
// gpio outputs
`SET_IO_OUTPUT (hp_Alarm,         4);
`SET_IO_OUTPUT (hp_Alarm_latch,   5);
`SET_IO_OUTPUT (hp_Alarm_ctr,     13:6);

endmodule
