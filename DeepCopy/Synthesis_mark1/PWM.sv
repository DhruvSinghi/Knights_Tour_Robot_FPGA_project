module PWM (
    input clk, rst_n,
    input [10:0] duty,
    output reg PWM_sig, PWM_sig_n
);

    logic [10:0] cnt;


    // Counter logic
    always_ff @(posedge clk or negedge rst_n) 
    begin
        if (!rst_n)
            cnt <= 0;
        else
            cnt <= cnt + 1;
    end

    // PWM signal generation
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            PWM_sig <= 1'b0;
        else
            PWM_sig <= cnt < duty;     // PWM signal driven by 'd'

assign PWM_sig_n = ~PWM_sig;  // Inverted PWM signal

endmodule

