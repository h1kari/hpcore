`timescale 1ns / 1ps

module hp_mod #(
    parameter INVERT = 0	
) (
    input  wire CK,
    output reg  CK2 = 0,
    input  wire VCC,
    output reg Data = 0
);

// create CK2 to run at half CK speed so we can catch inverse phase glitches
always @(posedge CK)
    CK2 <= !CK2;

// create ring oscillator with data at CK2/2
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
    input  wire VCC,
    input  wire Data,
    output wire Alarm    
);

// create our A & B values for
// alarm = !x * !y = !(Data ^ B) * !(B ^ A) 
reg B = 0, A = 0;

always @(posedge CK)
    // use CK/CK2 to let us do posedge or negedge triggering
    if (CK2 == INVERT)
        // disable output if VCC is low
        if(VCC == 0)
            #0.1 B <= 0;
        else
            #0.1 B <= Data;

always @(posedge CK)
    // use CK/CK2 to let us do posedge or negedge triggering
    if (CK2 != INVERT)
        // disable output if VCC is low
        if(VCC == 0)
            #0.1 A <= 0;
        else
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

wire Alarm_w;
hp_pd #(INVERT) hp_pd (
    .CK(CK),
    .CK2(CK2),
    .VCC(VCC),
    .Data(Data ^ glitch),
    .Alarm(Alarm_w)
);

// delay VCC signal to enable Alarm output after phase detector has started up
reg [2:0] VCC_ = 0;
always @(posedge CK2)
    VCC_ <= {VCC_[1:0], VCC};

// only output Alarm when VCC is high
assign Alarm = Alarm_w & VCC_[2] & VCC;

endmodule
