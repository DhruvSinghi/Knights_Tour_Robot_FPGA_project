module RemoteComm_e(
			input clk, rst_n,
			input send_cmd,
			input [15:0] cmd,
			input RX,
			output logic cmd_sent,
			output logic [7:0] resp,	//A5
			output logic resp_rdy,
			output TX,
			output logic clr_resp_rdy
		);

  typedef enum reg [1:0] { IDLE, MSB, LSB } remotecomm_op_t;
  remotecomm_op_t state, nxt_state;

  logic trmt;
  logic tx_done;
  logic [7:0] LSB_cmd;  // to hold MSB of command
  logic sel_high;	// to hold LSB, sel line
  logic set_cmd_sent, reset_cmd_sent; 	
  logic [7:0] tx_data;
  

  UART iUART1 (.clk(clk), .rst_n(rst_n), .trmt(trmt), .tx_done(tx_done), .tx_data(tx_data), .rx_data(resp), .rx_rdy(resp_rdy), .TX(TX), .RX(RX), .clr_rx_rdy(clr_resp_rdy));

  always_ff @(posedge clk, negedge rst_n)
    if(!rst_n) state <= IDLE;	    
    else       state <= nxt_state; 

// send MSB first and then send LSB
  always_comb	begin
   set_cmd_sent = 'h0;
   reset_cmd_sent = 'h0;
   sel_high = 'h0;
   nxt_state = state;
   clr_resp_rdy = 1'b0;
   trmt = 'h0;

		case(state)
			MSB: begin		
				if(tx_done) begin	// automatically reset cmd_sent
					sel_high = 1'b0;
					trmt = 1'b1;
					nxt_state = LSB;
					end
				end
			LSB: begin
				if(tx_done) begin
					set_cmd_sent = 1'b1;
					nxt_state = IDLE;
					end
				end 
			
			default: 	//default case is IDLE
				if(send_cmd) begin
					sel_high = 1'b1;
					trmt = 1'b1;
					clr_resp_rdy = 1'b1;
					nxt_state = MSB;
				end
		endcase
	end

  // to hold LSB of cmd
  always_ff @(posedge clk, negedge rst_n)
	if(!rst_n) 
		LSB_cmd <= 1'b0;
	else if(send_cmd)
		LSB_cmd <= cmd[7:0];
  // the design is based on conditionally enabled flops 

  assign tx_data = sel_high ? cmd[15:8] : LSB_cmd;

  // SR flip-flop for cmd_rdy signal
  always_ff @(posedge clk or negedge rst_n) begin
   	if (!rst_n)
        cmd_sent <= 1'b0;                // Reset cmd_rdy signal
    	else begin
        	if (set_cmd_sent)                
            		cmd_sent <= 1'b1; 
        	else if (send_cmd || reset_cmd_sent)         
            		cmd_sent <= 1'b0;  
    		end
	end

endmodule

 
			
			