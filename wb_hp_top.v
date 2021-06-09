`default_nettype none

module wb_hp_top #(
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
    output wire          o_wb_ack,       // request is completed 
    output wire          o_wb_stall,     // cannot accept req
    output wire [31:0]   o_wb_data,      // output data

    // buttons
    input  wire [18:0]   gpio_i,
    output reg  [18:0]   gpio_enb,        // not enable - low for active
    output reg  [18:0]   gpio_o,
    
    // glitch test input, hard wire to 0 to disable
    input wire           glitch
);

wire [2:0] o_wb_ack_, o_wb_stall_;
wire [31:0] o_wb_data_ [2:0];
reg  [18:0] gpio_i_ [2:0];
wire [18:0] gpio_o_ [2:0];
wire [18:0] gpio_enb_ [2:0];

genvar i;
generate
    for (i = 0; i < 3; i = i + 1)
    begin
        wb_hp #(
            .DESIGN(i),
            .BASE_ADDRESS(32'h3000_0000 + (i * 4))
        ) wb_hp_p (
            .clk(clk),
            .reset(reset),
            .i_wb_cyc(i_wb_cyc),
            .i_wb_stb(i_wb_stb),
            .i_wb_we(i_wb_we),
            .i_wb_addr(i_wb_addr),
            .i_wb_data(i_wb_data),
            .o_wb_ack(o_wb_ack_[i]),
            .o_wb_stall(o_wb_stall_[i]),
            .o_wb_data(o_wb_data_[i]),
            .gpio_i(gpio_i_[i]),
            .gpio_o(gpio_o_[i]),
            .gpio_enb(gpio_enb_[i]),
        );
    end
endgenerate

// or wishbone buses together so they share the same wishbone bus
assign o_wb_ack   = |o_wb_ack_;
assign o_wb_stall = |o_wb_stall_;

genvar j, k;
wire [2:0] o_wb_data__ [31:0];
generate
    for (j = 0; j < 32; j = j + 1)
    begin
        for (k = 0; k < 3; k = k + 1)
        begin
            assign o_wb_data__[j][k] = o_wb_data_[k][j];
        end
        assign o_wb_data[j] = |o_wb_data__[j];
    end
endgenerate

// assign every 5 bits of gpio to each core
// unfortunately there isn't enough pins for the counter
always @(posedge clk) begin
    // enable top 3 bits for input
    gpio_enb[17:15] = 3'b111;
    // use them to mux access to control signals or counters
    case(gpio_i[17:15])
    0: begin
        gpio_enb[14:0]   <= {15{1'b0}};
        gpio_enb[14:0]   <= gpio_enb_[0][14:0];
        gpio_o[14:0]     <= gpio_o_[0][14:0];
        gpio_i_[0][14:0] <= gpio_i[14:0];
    end
    1: begin
        gpio_enb[14:0]   <= {15{1'b0}};
        gpio_enb[14:0]   <= gpio_enb_[1][14:0];
        gpio_o[14:0]     <= gpio_o_[1][14:0];
        gpio_i_[1][14:0] <= gpio_i[14:0];
    end
    2: begin
        gpio_enb[14:0]   <= {15{1'b0}};
        gpio_enb[14:0]   <= gpio_enb_[2][14:0];
        gpio_o[14:0]     <= gpio_o_[2][14:0];
        gpio_i_[2][14:0] <= gpio_i[14:0];
    end
    4: begin
        gpio_enb[4:0]    <= gpio_enb_[0][4:0];
        gpio_enb[9:5]    <= gpio_enb_[1][4:0];
        gpio_enb[14:10]  <= gpio_enb_[2][4:0];
        gpio_o[4:0]      <= gpio_o_[0][4:0];
        gpio_o[9:5]      <= gpio_o_[1][4:0];
        gpio_o[14:10]    <= gpio_o_[2][4:0];
        gpio_i_[0][4:0]  <= gpio_i[4:0];
        gpio_i_[1][4:0]  <= gpio_i[9:5];
        gpio_i_[2][4:0]  <= gpio_i[14:10];
    end
    endcase
end

endmodule
