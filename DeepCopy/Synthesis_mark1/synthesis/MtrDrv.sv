module MtrDrv(
input reg signed [10:0] lft_spd,
input reg signed [10:0] rght_spd,
input reg clk,rst_n,
output reg lftPWM1,
output reg lftPWM2,
output reg rghtPWM1,
output reg rghtPWM2
);

PWM idUT(.clk(clk),.rst_n(rst_n),.duty($signed(lft_spd+11'h400)),.PWM_sig(lftPWM1),.PWM_sig_n(lftPWM2));
PWM jDUT(.clk(clk),.rst_n(rst_n),.duty($signed(rght_spd+11'h400)),.PWM_sig(rghtPWM1),.PWM_sig_n(rghtPWM2));

endmodule
