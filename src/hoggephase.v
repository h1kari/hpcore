`timescale 1ns / 1ps

module hp_mod #(
    parameter INVERT = 0	
) (
    input  wire ck,
    output reg  ck2,
    input  wire vcc,
    input  wire reset,
    output reg  data
);

always @(posedge ck)
    if (reset)
        ck2 <= 0;
    else
        ck2 <= !ck2;

// create ring oscillator with data at f/2
always @(posedge ck)
    if (reset)
        #0.2 data <= 0;
    else if (ck2 == INVERT) begin
        #0.2 data <= ~data;
    end

endmodule


module hp_pd #(
    parameter INVERT = 0	
) (
    input  wire ck,
    input  wire reset,
    input  wire ck2,
    input  wire data,
    output wire alarm    
);

// create our A & B values for
// alarm = !x * !y = !(Data ^ B) * !(B ^ A) 
reg b, a;

always @(posedge ck)
    if (ck2 == INVERT)
        if (reset)
            #0.1 b <= 0;
        else
            #0.1 b <= data;

always @(posedge ck)
    if (ck2 != INVERT)
        if (reset)
            #0.1 a <= 0;
        else
            #0.1 a <= b;

wire y, x;
assign y = data ^ b;
assign x = b ^ a;
assign alarm = (~x) & (~y);

endmodule


module hoggephase #(
    parameter INVERT = 0	
) (
    input  wire ck,
    input  wire vcc,
    output wire alarm,
    input  wire glitch
);

wire data;
wire ck2;
hp_mod #(INVERT) hp_mod (
    .ck(ck),
    .ck2(ck2),
    .reset(!vcc),
    .vcc(vcc),
    .data(data)
);

hp_pd #(INVERT) hp_pd (
    .ck(ck),
    .ck2(ck2),
    .reset(!vcc),
    .data(data ^ glitch),
    .alarm(alarm)
);

endmodule
