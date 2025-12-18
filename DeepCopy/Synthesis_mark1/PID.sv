module PID(
		input clk, rst_n,
		input moving,		// Clear I_term if not moving
		input err_vld,		// Compute I & D again when vld
		input signed [11:0] error, 		// Signed error into PID
		input signed [9:0] frwrd,		// Summed with PID to form lft_spd,right_spd
		output logic signed [10:0] lft_spd, rght_spd 	// out These form the input to mtr_drv
	);


logic signed [10:0] frwrd_ZE;
logic signed [13:0] P_term_SE;
logic signed [13:0] I_term_SE;
logic signed [13:0] D_term_SE;
logic signed [13:0] PID;
logic signed [10:0] lft_spd_unsat;
logic signed [10:0] rght_spd_unsat;

logic signed [9:0] err_sat_ff;
logic signed err_vld_ff;


/////////////////////////
/////// P_term	/////////
/////////////////////////
logic signed [13:0] P_term;
logic signed [9:0] err_sat;
// localparam P_COEFF = 6'h10;	// 6'd16

assign err_sat = (!error[11] && |error[10:9]) ? 10'h1FF:	//01_1111_1111
		 (error[11] && !(&error[10:9])) ? 10'h200:	//10_0000_0000
		 {error[11], error[8:0]};		//sign extension

always_ff @(posedge clk or negedge rst_n)
	if(!rst_n) begin
		err_sat_ff <= '0;
		err_vld_ff <= 0;
	end
	else begin
		err_sat_ff <= err_sat;
		err_vld_ff <= err_vld;
	end

// assign P_term = err_sat_ff * $signed(P_COEFF);	
// assign P_term = err_sat << 4;
assign P_term = {err_sat_ff, 4'b0000};


/////////////////////////
/////// I_term	/////////
/////////////////////////
logic [8:0] I_term;
logic signed [14:0] integrator, nxt_integrator;
logic ov;					//overflow flag
logic signed [14:0] int_add0;			//holds value after addition
logic signed [14:0] err_ext; 			//sign extended register

//sign extension
assign err_ext = {{5{err_sat_ff[9]}}, err_sat_ff};
 
assign int_add0 = err_ext + integrator;

//overflow check
assign ov = (err_ext[14] == integrator[14]) && (err_ext[14] != int_add0[14]);

// Integrator register
always_ff @(posedge clk, negedge rst_n)
	if (!rst_n)
		integrator <= 16'h0000; 
	else
		integrator <= nxt_integrator;

//if moving = 1, ov = 0 and err_vld = 1, then nxt_integer value gets updated
assign nxt_integrator = moving ? ((!ov && err_vld_ff) ? int_add0 : integrator) : 16'h0000;

assign I_term = integrator[14:6];



/////////////////////////
/////// D_term	/////////
///////////////////////// 
logic signed [12:0] D_term;                
//localparam D_COEFF = 5'h07;                    		// Coefficient for the derivative term
logic signed [9:0] D_diff;                     		// Difference between current and previous error
logic signed [7:0] D_diff_sat;                		// Saturated difference
logic signed [9:0] prev_err1, prev_err2, prev_err3; 	// Previous error values for differentiation


// Sequential logic to update previous errors on valid signal
always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) begin
        prev_err1 <= 10'h000;                  
        prev_err2 <= 10'h000;
        prev_err3 <= 10'h000;
    end
    else if (err_vld_ff) begin                    // Update previous errors when valid signal is high
        prev_err1 <= err_sat_ff;
        prev_err2 <= prev_err1;
        prev_err3 <= prev_err2;
    end
end


// Calculate the difference for derivative calculation
// No division by ?t required, as we only need proportional change
assign D_diff = err_sat_ff - prev_err3;

// Saturation logic for the derivative difference
assign D_diff_sat = (!D_diff[9] && |D_diff[8:7]) ? 8'h7F:    	// Positive saturation --> 8'h0111_1111
                    (D_diff[9] && !(&D_diff[8:7])) ? 8'h80: 	// Negative saturation --> 8'h1000_0000
                    {D_diff[9], D_diff[6:0]};                 	// Sign extension

// Calculate the derivative term
//assign D_term = (D_diff_sat) * $signed(D_COEFF);
 assign D_term = ($signed({{2{D_diff_sat[7]}}, D_diff_sat, 3'b000})) - $signed(D_diff_sat);



// Calculating the PID term
// divide P term by 2 and SignEx to 14 bits
// assign P_term_div = P_term >> 1;	
assign P_term_SE = {P_term[13], P_term[13], P_term[13:1]};
//assign P_term_SE = {P_term[12],(P_term >>> 1)};

// SignEx I_term(9) and D_term (13) to 14 bits
assign I_term_SE = {{6{I_term[8]}}, I_term[8:0]};
assign D_term_SE = {D_term[12] , D_term[12:0]};



// now add all of them to get the value of PID
// As I term is a late arriving signal, 
// assign PID = P_term_SE + I_term_SE + D_term_SE;

always_ff @(posedge clk or negedge rst_n)
	if(!rst_n)
		PID <= '0;
	else
		PID <= P_term_SE + I_term_SE + D_term_SE;

// Zero extending the forward bits
//assign frwrd_ZE =  {1'b0, frwrd};

always_ff @(posedge clk, negedge rst_n)
	if(!rst_n)
		frwrd_ZE <= 0;
	else
		frwrd_ZE <= {1'b0, frwrd};

assign lft_spd_unsat = moving ? $signed(frwrd_ZE + PID[13:3]) : 11'h000;
assign rght_spd_unsat = moving ? $signed(frwrd_ZE - PID[13:3]) : 11'h000;

// Since frwrd speed is only a positive number we only have to worry about
// + saturation. For left if PID positive and the sum with frwrd resulted in
// negative we need to saturate to 0x3FF.

assign lft_spd = (!PID[13] && lft_spd_unsat[10]) ? 10'h3FF : lft_spd_unsat;
assign rght_spd = (PID[13] && rght_spd_unsat[10]) ? 10'h3FF : rght_spd_unsat;

/*always_ff @(posedge clk or negedge rst_n)
	if(!rst_n) begin
		lft_spd <= '0;
		rght_spd <= 0;
	end
	else begin
		lft_spd <= (!PID[13] && lft_spd_unsat[10]) ? 10'h3FF : lft_spd_unsat;
		rght_spd <= (PID[13] && rght_spd_unsat[10]) ? 10'h3FF : rght_spd_unsat;
	end
*/

endmodule
