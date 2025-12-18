module rst_synch (
			input clk, RST_n,
			output logic rst_n
		);


// neagtive edge triggered flops to solve problems due to asynch reset which is asserted during negedge clkmodule reset_synch
 
logic rst_n_ff1, rst_n_ff2;

always_ff @(posedge clk or negedge RST_n) begin
    if (!RST_n) begin
        rst_n_ff1 <= 1'b0;
        rst_n_ff2 <= 1'b0;
    end else begin
        rst_n_ff1 <= 1'b1;
        rst_n_ff2 <= rst_n_ff1;
    end
end

assign rst_n = rst_n_ff2;

endmodule
