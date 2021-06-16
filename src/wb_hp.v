`default_nettype none

/*
 * This whole file builds a GPIO and wishbone interface for
 * interacting with the hoggephase module. It instatiates
 * both a positive & negative version of the hoggephase
 * detector and then adds on a latch to save the alarm
 * signal and a counter to see if multiple alarms are caught.
 * 
 * GPIO / Wishbone I/O:
 * 0      vcc            [I]
 * 1      alarm_rst      [I]
 * 2      alarm_ctr_rst  [I]
 * 3      glitch         [I]
 * 4      alarm          [O]
 * 5      alarm_latch    [O]
 * 6:13   alarm_ctr      [O]
 * 15:14  pn_select      [I]
 */

//`define USE_POWER_PINS 1
`define IO_INPUT  1'b1
`define IO_OUTPUT 1'b0
    

/*
 * Simulate glitches to test detection capability
 * We're a bit limited with this because we can only generate
 * glitches synchronously (easily). Note that if this accidentally
 * gets triggered by a glitch event, it will insert glitches 137
 * clock cycles after the glitch event.
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

reg [10:0] counter;
reg glitch_r;
always @(posedge clk)
begin
    glitch_r <= 0;
    if (reset | !enable)
        counter <= 0;
    // increment counter if enabled, but don't repeat
    else if (enable & ~counter[10])
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


/*
 * For our glitch latches they can sometimes be reset if
 * their reset signals are themselves glitched. To prevent
 * this we use a shift register to ensure that the reset is
 * held high for RESET_SHR clock cycles to generate our
 * actual reset.
 */
module reset_shr #(
    parameter RESET_SHR = 16
) (
    input  wire clk,
    input  wire reset,
    output wire reset_shr
);

// use shift register to make sure reset is held high for 16 clock cycles to try to prevent glitches from resetting latch
reg  [RESET_SHR-1:0] shr;
always @(posedge clk)
    shr <= {shr[RESET_SHR-1:0], reset};

// reset_shr only goes high when all bits of shr are high
assign reset_shr = &shr;

endmodule


/*
 * Implement a latch that will go high if an alarm
 * signal is detected. Alarm signals go high between
 * clock cycles so they can't be latched synchronously
 * which may create some issues on FPGA vs ASIC vs SIM.
 */
module hp_alarm_latch #(
    parameter RESET_SHR = 16
) (
    input  wire clk,
    input  wire reset,
    input  wire hp_alarm,
    output reg  hp_alarm_latch
);

// anti-glitch our reset
wire reset_shr;
reset_shr #(RESET_SHR) reset_shr_inst (
    .clk(clk),
    .reset(reset),
    .reset_shr(reset_shr)
);

always @(*)
begin
    if (reset_shr)
        hp_alarm_latch <= 0;
    else if (hp_alarm)
        hp_alarm_latch <= 1;
end

endmodule


/*
 * Increment a counter for every alarm signal that's
 * detected. This is a bit tricky as we need to first
 * convert the alarm to a synchronous signal and then
 * use that to increment a counter synchronously.
 * The limitation of this method is that we will not
 * increment for multiple glitches per clock cycle
 * but should give us a general idea of how many glitches
 * have happened over time. Note that this register can
 * be effected by the glitch itsself and may be reset
 * or end up with a strange count value some of the time.
 */
module hp_alarm_ctr #(
    parameter RESET_SHR = 16
) (
    input  wire      clk,
    input  wire      reset,
    input  wire      hp_alarm,
    output reg [7:0] hp_alarm_ctr
);

// anti-glitch our reset
wire reset_shr;
reset_shr #(RESET_SHR) reset_shr_inst (
    .clk(clk),
    .reset(reset),
    .reset_shr(reset_shr)
);

// create separate latch that's reset after we've generated our sync signal
reg latch_sync, latch_async, latch_async_0;
always @(*)
begin
    if (latch_sync | reset_shr)
        latch_async <= 0;
    else if (hp_alarm & !latch_async_0)
        latch_async <= 1;
end

// generate signal that goes high on positive edge of hp_alarm_latch that is synchronous to clock
always @(posedge clk)
begin
    if (reset_shr)
        latch_sync <= 0;
    else
    begin
        if (latch_async & !latch_async_0)
            latch_sync <= 1;
        else
            latch_sync <= 0;
    end
    latch_async_0 <= latch_async;
end

// implement counter clocked by alarm signal, this in theory shouldn't be faster than the speed of clk ?
always @(posedge clk)
begin
    if (reset_shr)
    begin
        hp_alarm_ctr <= 0;
    end
    else
    begin
        if (latch_sync)
            hp_alarm_ctr <= hp_alarm_ctr + 1;
    end  
end

endmodule


/*
 * Caravel peripheral implementing wishbone & GPIO interface.
 * Upper level wrapper should tie this into the LA or other
 * buses if needed. 
 *
 * BASE_ADDRESS - Address of single 32-bit register on wishbone bus
 * GLITCH_BIST  - Build in built-in self-test for glitch detection
 * RESET_SHR    - Size of shift register to use for reset glitch protection
 */
module wb_hp #(
    parameter   [31:0]  BASE_ADDRESS = 32'h3000_0000,        // base address
    parameter           GLITCH_BIST  = 1,
    parameter           RESET_SHR    = 16
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
    input  wire          wb_clk_i,        // wishbone clock
    input  wire          reset,           // peripheral reset

    input  wire          user_clock2,     // hoggephase actually clocked on this

    // wb interface
    input  wire          wbs_cyc_i,       // wishbone transaction
    input  wire          wbs_stb_i,       // strobe - data valid and accepted as long as !wbs_stall_o
    input  wire          wbs_we_i,        // write enable
    input  wire [31:0]   wbs_adr_i,       // address
    input  wire [31:0]   wbs_dat_i,       // incoming data
    output reg           wbs_ack_o,       // request is completed 
    output wire          wbs_stl_o,       // cannot accept req
    output reg  [31:0]   wbs_dat_o,       // output data

    // buttons
    input  wire [15:0]   gpio_i,
    output wire [15:0]   gpio_enb,        // not enable - low for active
    output wire [15:0]   gpio_o,
    
    output wire          glitch           // glitch output for simulation purposes
);

wire clk = user_clock2;
       
wire       hp_alarm;
wire       hp_vcc,    hp_glitch_en;
reg        wb_hp_vcc, wb_hp_glitch_en;
wire [1:0] hp_pn_select;
reg  [1:0] wb_hp_pn_select;

generate
    if (GLITCH_BIST)
    begin
        hp_glitcher
        hp_glitcher
        (
            .clk(clk),
            .reset(reset),
            .enable(hp_glitch_en | wb_hp_glitch_en),
            .glitch(glitch)
        );
    end
    else
        assign glitch = 0;
endgenerate

wire hp_alarm_p, hp_alarm_n;
hoggephase #(0)
hoggephase_p
(
    .ck(clk),
    .vcc(hp_vcc | wb_hp_vcc),
    .alarm(hp_alarm_p),
    .glitch(glitch)
);
hoggephase #(1)
hoggephase_n
(
    .ck(clk),
    .vcc(hp_vcc | wb_hp_vcc),
    .alarm(hp_alarm_n),
    .glitch(glitch)
);

// select which detectors to use...
assign hp_alarm = ((hp_pn_select[0] | wb_hp_pn_select[0]) & hp_alarm_p) |
                  ((hp_pn_select[1] | wb_hp_pn_select[1]) & hp_alarm_n);
    
assign wbs_stl_o = 0;

// instantiate alarm latch
wire hp_alarm_rst;
reg  wb_hp_alarm_rst;
wire hp_alarm_latch;
hp_alarm_latch #(RESET_SHR) hp_alarm_latch_inst (
    .clk(clk),
    .reset(hp_alarm_rst | wb_hp_alarm_rst | reset),
    .hp_alarm(hp_alarm),
    .hp_alarm_latch(hp_alarm_latch)
);

// instantiate alarm latch counter
wire hp_alarm_ctr_rst;
reg wb_hp_alarm_ctr_rst;
wire [7:0] hp_alarm_ctr;
hp_alarm_ctr #(RESET_SHR) hp_alarm_ctr_inst (
    .clk(clk),
    .reset(hp_alarm_ctr_rst | wb_hp_alarm_ctr_rst | reset),
    .hp_alarm(hp_alarm),
    .hp_alarm_ctr(hp_alarm_ctr)
);

// handle wishbone writes
always @(posedge wb_clk_i)
begin
    if (reset)
    begin
        wb_hp_vcc           <= 0;
        wb_hp_alarm_rst     <= 0;
        wb_hp_alarm_ctr_rst <= 0;
        wb_hp_glitch_en     <= 0;
        wb_hp_pn_select     <= 0;
    end
    else if (wbs_stb_i && wbs_cyc_i && wbs_we_i && !wbs_stl_o &&
             wbs_adr_i == BASE_ADDRESS)
    begin
        wb_hp_vcc           <= wbs_dat_i[0];
        wb_hp_alarm_rst     <= wbs_dat_i[1];
        wb_hp_alarm_ctr_rst <= wbs_dat_i[2];
        wb_hp_glitch_en     <= wbs_dat_i[3];
        wb_hp_pn_select     <= wbs_dat_i[15:14];
    end
end

// handle wishbone reads
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
                          hp_alarm_ctr, hp_alarm_latch, hp_alarm,
                          wb_hp_glitch_en, wb_hp_alarm_ctr_rst,
                          wb_hp_alarm_rst, wb_hp_vcc};
        end
        else
        begin
            wbs_dat_o <= 32'h0;
        end
    end
end

// handle wishbone acks
always @(posedge wb_clk_i)
begin
    if (reset)
        wbs_ack_o <= 0;
    else
        // return ack immediately
        wbs_ack_o <= (wbs_stb_i && !wbs_stl_o && (wbs_adr_i == BASE_ADDRESS));
end

// some macros to help with setting GPIO
`define SET_IO_OUTPUT(sig, pin) \
    assign gpio_enb[pin] = {16{`IO_OUTPUT}}; \
    assign gpio_o[pin] = sig
`define SET_IO_INPUT(sig, pin) \
    assign gpio_enb[pin] = {16{`IO_INPUT}}; \
    assign sig = gpio_i[pin] 
`define SET_IO_NA(pin) \
    assign gpio_enb[pin] = {16{`IO_INPUT}}

// gpio inputs
`SET_IO_INPUT  (hp_vcc,           0);
`SET_IO_INPUT  (hp_alarm_rst,     1);
`SET_IO_INPUT  (hp_alarm_ctr_rst, 2);
`SET_IO_INPUT  (hp_glitch_en,     3);
`SET_IO_INPUT  (hp_pn_select,     15:14);
    
// gpio outputs
`SET_IO_OUTPUT (hp_alarm,         4);
`SET_IO_OUTPUT (hp_alarm_latch,   5);
`SET_IO_OUTPUT (hp_alarm_ctr,     13:6);

endmodule
