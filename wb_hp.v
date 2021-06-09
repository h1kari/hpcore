`default_nettype none

//`define USE_POWER_PINS 1
`define IO_INPUT  1'b1
`define IO_OUTPUT 1'b0
`define SET_IO_OUTPUT(sig, pin) \
    gpio_enb[pin] <= {16{`IO_OUTPUT}}; \
    gpio_o[pin] <= sig
`define SET_IO_INPUT(sig, pin) \
    gpio_enb[pin] <= {16{`IO_INPUT}}; \
    sig <= gpio_i[pin] 
`define SET_IO_NA(pin) \
    gpio_enb[pin] <= {16{`IO_INPUT}}
    
/* gpio/wb settings:
 * 0 - vcc           [I]
 * 1 - Alarm_rst     [I]
 * 2 - Alarm_ctr_rst [I]
 * 3 - Alarm         [O]
 * 4 - Alarm_latch   [O]
 * 5:12 - Alarm_ctr  [O]
 *
 * design options:
 * 0 - only positive detector
 * 1 - only negative detector
 * 2 - both detectors
 */

module wb_hp #(
    parameter   [1:0]   DESIGN             = 2,
    parameter   [31:0]  BASE_ADDRESS       = 32'h3000_0000        // base address
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
    input  wire          clk,
    input  wire          reset,

    // wb interface
    input  wire          i_wb_cyc,       // wishbone transaction
    input  wire          i_wb_stb,       // strobe - data valid and accepted as long as !o_wb_stall
    input  wire          i_wb_we,        // write enable
    input  wire  [31:0]  i_wb_addr,      // address
    input  wire  [31:0]  i_wb_data,      // incoming data
    output reg           o_wb_ack,       // request is completed 
    output wire          o_wb_stall,     // cannot accept req
    output reg  [31:0]   o_wb_data,      // output data

    // buttons
    input  wire [12:0]   gpio_i,
    output wire [12:0]   gpio_enb,        // not enable - low for active
    output wire [12:0]   gpio_o,
    
    // glitch test input, hard wire to 0 to disable
    input wire           glitch
);
       
wire hp_Alarm;
wire hp_vcc;
reg wb_hp_vcc;

generate
    if(DESIGN == 0)
    begin
        hoggephase #(0) hoggephase (
            .CK(clk),
            .VCC(hp_vcc | wb_hp_vcc),
            .Alarm(hp_Alarm),
            .glitch(glitch)
        );
    end
    else if(DESIGN == 1)
    begin
        hoggephase #(1) hoggephase (
            .CK(clk),
            .VCC(hp_vcc | wb_hp_vcc),
            .Alarm(hp_Alarm),
            .glitch(glitch)
        );
    end
    else if(DESIGN == 2)
    begin
        wire hp_Alarm_p, hp_Alarm_n;
        hoggephase #(0) hoggephase_p (
            .CK(clk),
            .VCC(hp_vcc | wb_hp_vcc),
            .Alarm(hp_Alarm_p),
            .glitch(glitch)
        );
        hoggephase #(1) hoggephase_n (
            .CK(clk),
            .VCC(hp_vcc | wb_hp_vcc),
            .Alarm(hp_Alarm_n),
            .glitch(glitch)
        );
        assign hp_Alarm = hp_Alarm_p | hp_Alarm_n;
    end
endgenerate
    
assign o_wb_stall = 0;

// latch Alarm to catch small glitches
reg hp_Alarm_latch = 0;
wire hp_Alarm_rst;
reg wb_hp_Alarm_rst = 0;
always @(hp_Alarm or hp_Alarm_rst or wb_hp_Alarm_rst)
    if(hp_Alarm_rst | wb_hp_Alarm_rst | reset)
        hp_Alarm_latch <= 0;
    else if(hp_Alarm)
        hp_Alarm_latch <= 1;

// implement counter clocked by alarm signal, this in theory shouldn't be faster than the speed of clk ?
reg [7:0] hp_Alarm_ctr = 0;
wire hp_Alarm_ctr_rst;
reg wb_hp_Alarm_ctr_rst = 0;
always @(hp_Alarm or hp_Alarm_ctr_rst or wb_hp_Alarm_ctr_rst)
    if(hp_Alarm_ctr_rst | wb_hp_Alarm_ctr_rst | reset)
        hp_Alarm_ctr <= 0;
    else if(hp_Alarm)
        hp_Alarm_ctr <= hp_Alarm_ctr + 1;

// writes
reg [7:0] Alarm_counter = 0;
always @(posedge clk) begin
    if(reset)
    begin
        wb_hp_vcc <= 0;
        wb_hp_Alarm_rst <= 0;
        wb_hp_Alarm_ctr_rst <= 0;
    end
    else if(i_wb_stb && i_wb_cyc && i_wb_we && !o_wb_stall && i_wb_addr == BASE_ADDRESS) begin
        wb_hp_vcc           <= i_wb_data[0];
        wb_hp_Alarm_rst     <= i_wb_data[1];
        wb_hp_Alarm_ctr_rst <= i_wb_data[2];
    end
end

// reads
always @(posedge clk) begin
    if(i_wb_stb && i_wb_cyc && !i_wb_we && !o_wb_stall && i_wb_addr == BASE_ADDRESS)
        o_wb_data <= {19'h0, hp_Alarm_ctr, hp_Alarm_latch, hp_Alarm, wb_hp_Alarm_ctr_rst, wb_hp_Alarm_rst, wb_hp_vcc};
    else
        o_wb_data <= 32'h0;
end

// acks
always @(posedge clk) begin
    if(reset)
        o_wb_ack <= 0;
    else
        // return ack immediately
        o_wb_ack <= (i_wb_stb && !o_wb_stall && (i_wb_addr[31:8] == BASE_ADDRESS));
end

always @(posedge clk) begin
    // gpio inputs
    `SET_IO_INPUT  (hp_vcc,           0);
    `SET_IO_INPUT  (hp_Alarm_rst,     1);
    `SET_IO_INPUT  (hp_Alarm_ctr_rst, 2);
    
    // gpio outputs
    `SET_IO_OUTPUT (hp_Alarm,         3);
    `SET_IO_OUTPUT (hp_Alarm_latch,   4);
    `SET_IO_OUTPUT (hp_Alarm_ctr,     12:5);
end

endmodule
