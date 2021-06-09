`timescale 1ns / 1ps

module hp_mod #(
    parameter INVERT = 0	
) (
    input  wire CK,
    input  wire VCC,
    output reg Data = 0
);

generate
    if (INVERT)
    begin
        // create ring oscillator with data at f/2
        always @(negedge CK)
        begin
            if(VCC == 0)
                #0.2 Data <= 0;
            else
                #0.2 Data <= ~Data;
        end
    end
    else
    begin
        // create ring oscillator with data at f/2
        always @(posedge CK)
        begin
            if(VCC == 0)
                #0.2 Data <= 0;
            else
                #0.2 Data <= ~Data;
        end
    end
endgenerate

endmodule


module hp_pd #(
    parameter INVERT = 0	
) (
    input  wire CK,
    input  wire Data,
    output wire Alarm    
);

// create our A & B values for
// alarm = !x * !y = !(Data ^ B) * !(B ^ A) 
reg B = 0, A = 0;

generate
    if (INVERT)
    begin
        always @(negedge CK)
            #0.1 B <= Data;

        always @(posedge CK)
            #0.1 A <= B;
    end
    else
    begin
        always @(posedge CK)
            #0.1 B <= Data;

        always @(negedge CK)
            #0.1 A <= B;
    end
endgenerate

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
hp_mod #(INVERT) hp_mod (
    .CK(CK),
    .VCC(VCC),
    .Data(Data)
);

hp_pd #(INVERT) hp_pd (
    .CK(CK),
    .Data(Data ^ glitch),
    .Alarm(Alarm)
);

endmodule
