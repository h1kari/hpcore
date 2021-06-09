`timescale 1ns / 1ps

module wb_hp_test();

reg clk = 0, reset;
reg i_wb_cyc, i_wb_stb, i_wb_we;
reg [31:0] i_wb_addr, i_wb_data;
wire o_wb_ack, o_wb_stall;
wire [31:0] o_wb_data;
wire [15:0] gpio_i, gpio_enb, gpio_o;
reg glitch = 0;

wb_hp wb_hp (
    .clk(clk),
    .reset(reset),

    // wb interface
    .i_wb_cyc(i_wb_cyc),       // wishbone transaction
    .i_wb_stb(i_wb_stb),       // strobe - data valid and accepted as long as !o_wb_stall
    .i_wb_we(i_wb_we),         // write enable
    .i_wb_addr(i_wb_addr),     // address
    .i_wb_data(i_wb_data),     // incoming data
    .o_wb_ack(o_wb_ack),       // request is completed 
    .o_wb_stall(o_wb_stall),   // cannot accept req
    .o_wb_data(o_wb_data),     // output data

    // buttons
    .gpio_i(gpio_i),
    .gpio_enb(gpio_enb),       // not enable - low for active
    .gpio_o(gpio_o),
    
    .glitch(glitch)
);

reg hp_vcc, hp_Alarm_rst, hp_Alarm_ctr_rst;
wire hp_Alarm, hp_Alarm_latch;
wire [7:0] hp_Alarm_ctr;

assign gpio_i = {13'h0, hp_Alarm_ctr_rst, hp_Alarm_rst, hp_vcc};
assign hp_Alarm = gpio_o[4];
assign hp_Alarm_latch = gpio_o[5];
assign hp_Alarm_ctr = gpio_o[15:8];

`define GLITCH \
    #0.1; \
    glitch <= 1; \
    #0.1; \
    glitch <= 0; \
    #0.1
`define WB_WRITE(addr, data) \
    @(posedge clk); \
    #0.1; \
    i_wb_stb  <= 1; \
    i_wb_cyc  <= 1; \
    i_wb_we   <= 1; \
    i_wb_addr <= addr; \
    i_wb_data <= data; \
    @(posedge clk); \
    #0.1; \
    i_wb_stb  <= 0; \
    i_wb_cyc  <= 0; \
    i_wb_we   <= 0; \
    i_wb_addr <= 0; \
    i_wb_data <= 0; \
    $display("wb_write(0x%x, 0x%x)", addr, data)
`define WB_READ(addr) \
    @(posedge clk); \
    #0.1; \
    i_wb_stb  <= 1; \
    i_wb_cyc  <= 1; \
    i_wb_we   <= 0; \
    i_wb_addr <= addr; \
    i_wb_data <= 0; \
    @(posedge clk); \
    #0.1; \
    i_wb_stb  <= 0; \
    i_wb_cyc  <= 0; \
    i_wb_we   <= 0; \
    i_wb_addr <= 0; \
    i_wb_data <= 0; \
    @(posedge clk); \
    $display("wb_read(0x%x) = 0x%x", addr, o_wb_data)
`define PRINT_STATS \
    $display("hp_vcc=%d hp_Alarm_rst=%d hp_Alarm_ctr_rst=%d hp_Alarm=%d hp_Alarm_latch=%d hp_Alarm_ctr=%d", \
        wb_hp_vcc, wb_hp_Alarm, wb_hp_Alarm_ctr_rst, wb_hp_Alarm, wb_hp_Alarm_latch, wb_hp_Alarm_ctr)
wire wb_hp_vcc = o_wb_data[0];
wire wb_hp_Alarm_rst = o_wb_data[1];
wire wb_hp_Alarm_ctr_rst = o_wb_data[2];
wire wb_hp_Alarm = o_wb_data[4];
wire wb_hp_Alarm_latch = o_wb_data[5];
wire [7:0] wb_hp_Alarm_ctr = o_wb_data[15:8];
always #0.5 clk <= !clk;

initial begin
    reset     <= 1;
    i_wb_cyc  <= 0;
    i_wb_stb  <= 0;
    i_wb_we   <= 0;
    i_wb_addr <= 0;
    i_wb_data <= 0;
    hp_vcc           <= 0;
    hp_Alarm_rst     <= 1;
    hp_Alarm_ctr_rst <= 1;
    
    #100;
    reset  <= 0;
    hp_vcc <= 1;
    #10;
    hp_Alarm_rst <= 0;
    hp_Alarm_ctr_rst <= 0;
    glitch <= 0;
    
    // test glitch detection!
    #1337;
    `GLITCH;
    #3;
    `GLITCH;
    #5;
    `GLITCH;
    #7;
    `GLITCH;
    #11;
    `GLITCH;
    #13;
    `GLITCH;
    #17;
    `GLITCH;
    #19;
    `GLITCH;
    #100;
    // verify in waveform that glitches line up and doesn't report "glitch not caught!!" :)
    
    // test Alarm_ctr_rst
    $display("\n*** TESTING hp_Alarm_ctr ***");
    $display("Alarm_ctr: %d", hp_Alarm_ctr);
    if(hp_Alarm_ctr < 8) $display("!!! FAIL !!!");
    else $display("pass");
    @(posedge clk);
    hp_Alarm_ctr_rst <= 1;
    @(posedge clk);
    hp_Alarm_ctr_rst <= 0;
    #10;
    @(posedge clk);
    $display("Alarm_ctr: %d", hp_Alarm_ctr);
    if(hp_Alarm_ctr != 0) $display("!!! FAIL !!!");
    else $display("pass");
    
    // test Alarm_latch_rst
    $display("\n*** TESTING hp_Alarm_latch ***");
    $display("Alarm_latch: %d", hp_Alarm_latch);
    if(hp_Alarm_latch != 1) $display("!!! FAIL !!!");
    else $display("pass");
    @(posedge clk);
    hp_Alarm_rst <= 1;
    @(posedge clk);
    hp_Alarm_rst <= 0;
    #10;
    @(posedge clk);
    $display("Alarm_latch: %d", hp_Alarm_latch);
    if(hp_Alarm_latch != 0) $display("!!! FAIL !!!");
    else $display("pass");
    #10;
    
    // test hp_vcc
    hp_vcc <= 0;
    #10;
    
    // test wishbone interface
    $display("\n*** TESTING hp_vcc ***");
    $display("reading hp_vcc == 0");
    `WB_READ (32'h3000_0000);
    `PRINT_STATS;
    `WB_WRITE(32'h3000_0000, 1);
    $display("reading hp_vcc == 1");
    `WB_READ (32'h3000_0000);
    `PRINT_STATS;
    if(wb_hp_vcc != 1) $display("!!! FAIL !!!");
    else $display("pass");
    
    // test hp_Alarm_latch
    $display("\n*** TESTING hp_Alarm_latch ***");
    `GLITCH;
    #10;
    $display("reading hp_Alarm_latch == 1");
    `WB_READ(32'h3000_0000);
    `PRINT_STATS;
    `WB_WRITE(32'h3000_0000, 2 | 1);
    #10;
    `WB_WRITE(32'h3000_0000, 1);
    $display("reading hp_Alarm_latch == 0");
    `WB_READ (32'h3000_0000);
    `PRINT_STATS;
    if(wb_hp_Alarm_latch != 0) $display("!!! FAIL !!!");
    else $display("pass");
    
    // test hp_Alarm_ctr_rst
    $display("\n*** TESTING hp_Alarm_ctr ***");
    `GLITCH;
    #10;
    $display("reading hp_Alarm_ctr == 3");
    `WB_READ (32'h3000_0000);
    `PRINT_STATS;
    `WB_WRITE(32'h3000_0000, 4 | 1);
    #10;
    `WB_WRITE(32'h3000_0000, 1);
    $display("reading hp_Alarm_ctr == 0");
    `WB_READ (32'h3000_0000);
    `PRINT_STATS;
    if(wb_hp_Alarm_ctr != 0) $display("!!! FAIL !!!");
    else $display("pass");
    #100;
    $finish;
end

always @(negedge glitch)
    if(!hp_Alarm) $display("!!! FAIL !!! Glitch not caught!!");

endmodule