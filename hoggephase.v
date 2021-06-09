`timescale 1ns / 1ps

module hp_mod #(
    parameter INVERT = 0	
) (
    input  wire CK,
    output reg  CK2 = 0,
    input  wire VCC,
    output reg Data = 0
);

always @(posedge CK)
    CK2 <= !CK2;

// create ring oscillator with data at f/2
always @(posedge CK)
    if (CK2 == INVERT) begin
        if(VCC == 0)
            #0.2 Data <= 0;
        else
            #0.2 Data <= ~Data;
    end

endmodule


module hp_pd #(
    parameter INVERT = 0	
) (
    input  wire CK,
    input  wire CK2,
    input  wire Data,
    output wire Alarm    
);

// create our A & B values for
// alarm = !x * !y = !(Data ^ B) * !(B ^ A) 
reg B = 0, A = 0;

always @(posedge CK)
    if (CK2 == INVERT)
        #0.1 B <= Data;

always @(posedge CK)
    if (CK2 != INVERT)
        #0.1 A <= B;

wire Y, X;
assign Y = Data ^ B;
assign X = B ^ A;
assign Alarm = (~X) & (~Y);

endmodule


module hoggephase #(
    parameter INVERT = 0	
) (
    input  wire CK,
    input  wire VCC,
    output wire Alarm,
    input  wire glitch
);

wire Data;
wire CK2;
hp_mod #(INVERT) hp_mod (
    .CK(CK),
    .CK2(CK2),
    .VCC(VCC),
    .Data(Data)
);

hp_pd #(INVERT) hp_pd (
    .CK(CK),
    .CK2(CK2),
    .Data(Data ^ glitch),
    .Alarm(Alarm)
);

endmodule
