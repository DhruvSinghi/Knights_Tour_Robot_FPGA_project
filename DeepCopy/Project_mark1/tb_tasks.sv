package tb_tasks;


logic signed [11:0] err;
logic [16:0] prev_omega;
int cntrIR_n_count = 0;
logic [14:0] prev_xx, prev_yy;
logic [14:0] last_xx, last_yy;
logic move_count;
int num_moves = 0;


  ///////////////////////////////////////////////
  /////// Initialize and Calibrate //////////////
  ///////////////////////////////////////////////
  
  task automatic initialize(ref clk, RST_n, rst_n, send_cmd, [15:0]cmd, [7:0] resp, ref NEMO_setup, ref resp_rdy, ref logic rghtPWM, ref logic lftPWM);
	 real Duty_lft, Duty_rght;
	 cmd = 0;
	 send_cmd = 0;
	 RST_n = 0;
	 clk = 0;
	 repeat (2) @(posedge clk);
	 @(negedge clk) RST_n = 1;
	 wait4sig(.clk(clk), .sig(rst_n));
	 $display(" inital coordinates of X: 2800 ");
	 $display(" inital coordinates of Y: 2800 "); 
	 PWM_to_Duty(.PWM(lftPWM), .Duty(Duty_lft));
	 PWM_to_Duty(.PWM(rghtPWM), .Duty(Duty_rght));
	 assert(Duty_lft === Duty_rght)
	 	$display(" PWM is running and Duty is %f", Duty_rght);
	
	send_command(.cmd_to_snd(16'h2000),.send_cmd(send_cmd),.cmd(cmd),.clk(clk));
	calibrate(.clk(clk), .resp(resp), .NEMO_setup(NEMO_setup), .resp_rdy(resp_rdy), .cmd(cmd), .send_cmd(send_cmd));

  endtask


  task automatic calibrate(ref clk, [15:0]cmd, [7:0] resp, ref NEMO_setup, ref resp_rdy ,  send_cmd);
          
	 fork
	  	begin: timeout
          		repeat (60000000) @(posedge clk);
          		$display(" FAIL: Timed out waiting for NEMO_setup");
	  	$stop();
         	end
	 	begin: check
          		@(posedge NEMO_setup) disable timeout;
          		$display(" SUCCESS: NEMO_setup is HIGH");
	 	end
	join

	 check4resp(clk, resp_rdy, resp);

	 assert(resp == 8'ha5)
	 	$display(" Success: Calibration done \n \n");
	 else
	 	$fatal(" Fail: Calibration Failed");

  endtask
	


   //////////////////////////////////////////////////
   //////// Testing with manual Commands  ///////////
   //////////////////////////////////////////////////


  task automatic X_Y_pos(ref logic clk, ref reg moving, [15:0] cmd, [11:0] desired_heading, ref logic [7:0] resp, ref resp_rdy, ref reg [14:0] xx, yy); 

	last_xx = xx;
	last_yy = yy;

	check4resp(.clk(clk), .resp_rdy(resp_rdy), .resp(resp));
		
	case(desired_heading[11:4])
		8'h00 : begin
				 if((yy[14:12] === (last_yy[14:12] + cmd[2:0])) && (xx[14:12] === last_xx[14:12]))
					move_count = 1;	
			end
		8'h3F : begin
				 if((yy[14:12] === last_yy[14:12]) && (xx[14:12] === (last_xx[14:12] - cmd[2:0])))
					move_count = 1;	
			end
		8'h7F : begin
				 if((yy[14:12] === last_yy[14:12] - cmd[2:0]) && (xx[14:12] === last_xx[14:12]))
					move_count = 1;	
			end
		8'hBF : begin
				 if((yy[14:12] === last_yy[14:12]) && (xx[14:12] === last_xx[14:12] + cmd[2:0]))
					move_count = 1;	
			end
		endcase
					 
		assert(move_count && (yy[11:0] > 12'h600 && yy[11:0] < 12'h999) && (xx[11:0] > 12'h600 && xx[11:0] < 12'h999))
			$display(" SUCCESS: X and Y coordinates are in expected range "); 
		else 		
			$error(" FAIL: X and Y coordinates not in expected range ");
		
		
		$display(" \t Current X Coordinate: %h", xx);
		$display(" \t Current Y Coordinate: %h", yy);
		
  endtask
 
 
  task automatic check_dirctn(ref [11:0] desired_heading, ref reg [9:0] frwrd, ref clk, ref reg [14:0] xx,yy);
	
	
	prev_xx = xx;
	prev_yy = yy;
	
	wait(frwrd === 12'h300);

	case(desired_heading[11:4])
		8'h00:	//north
			assert($signed(yy) > $signed(prev_yy)) 
				$display(" Success: Expected move: NORTH, Actual move: NORTH");
			else 
				$error(" Fail: Expected move: NORTH, Actual move: SOUTH");
		8'h3f:  //west
			assert($signed(xx) < $signed(prev_xx)) 
				$display(" Success: Expected move: WEST, Actual move: WEST");
			else 
				$error(" Fail: Expected move: WEST, Actual move: EAST");
		8'h7f:  //south
			assert($signed(yy) < $signed(prev_yy)) 
				$display(" Success: Expected move: SOUTH, Actual move: SOUTH ");
			else 
				$error("Fail: Expected move: SOUTH, Actual move: NORTH");
		8'hbf:  //east
			assert($signed(xx) > $signed(prev_xx)) 
				$display(" Success: Expected move: EAST, Actual move: EAST ");
			else 
				$error(" Fail: Expected move: EAST, Actual move: WEST");
	endcase

  endtask


  task automatic Duty_check(ref logic rghtPWM, ref logic lftPWM, logic signed [11:0] error, ref logic moving, ref clk);
	real Duty_rght, Duty_lft;
	wait4sig(.clk(clk), .sig(moving));
	PWM_to_Duty(.PWM(lftPWM), .Duty(Duty_lft));
	PWM_to_Duty(.PWM(rghtPWM), .Duty(Duty_rght));
	if(error >= $signed(12'd800))
		assert(Duty_rght < Duty_lft) 
			$display(" Change in Direction Detected: Moving Right, Right Duty: %f, Left Duty: %f", Duty_rght, Duty_lft);
		else 
			$error(" FAIL: Should move Right to reduce error but moved Left, Right Duty: %f, Left Duty: %f", Duty_rght, Duty_lft);
	else if(error <= $signed(-12'd800))
		assert(Duty_rght > Duty_lft) 
			$display(" Change in Direction Detected: Moving Left, Right Duty: %f, Left Duty: %f", Duty_rght, Duty_lft);
		else 
			$error(" FAIL: Should move Left to reduce error but moved Right, Right Duty: %f, Left Duty: %f", Duty_rght, Duty_lft);
  endtask 	

  task automatic PWM_to_Duty(ref logic PWM, output real Duty);
	real time1, time2, Ton, Toff;
	@(posedge PWM) time1 = $time;
        @(negedge PWM) Ton = $time - time1;
	time2 = $time;
	@(posedge PWM) Toff = $time - time2;

	Duty = Ton / (Ton + Toff);

  endtask

  task automatic check_heading( ref logic signed [11:0] heading, ref [11:0] desired_heading);
	err = desired_heading - heading;
	assert( err >= $signed(-12'h040) && err <= $signed(12'h040))
		$display(" SUCCESS: Heading reached Desired Heading, Heading: %h, Desired Heading: %h", heading, desired_heading);
	else
		$error(" FAIL: Unexpected Heading, Heading: %h, Desired Heading: %h", heading, desired_heading);
	
		$display(" \n \n ");
  endtask
  
  task automatic check_omega(ref reg signed [16:0] omega_sum, ref reg [9:0] frwrd, ref logic moving);
	@(posedge moving);
        prev_omega = omega_sum;
	wait(frwrd === 12'h300);
	assert(omega_sum > prev_omega) 
		$display(" SUCCESS: Omega Sum Ramped Up, initial Omega Sum: %h, current Omega Sum: %h", prev_omega, omega_sum);
	else 
		$error(" FAIL: Omega Sum does not Ramp Up, initial Omega Sum: %h, current Omega Sum: %h", prev_omega, omega_sum);
  endtask

  task automatic cntrIR_n_fires(ref reg cntrIR_n);
   repeat(2) @(posedge cntrIR_n) cntrIR_n_count++;
	assert(cntrIR_n_count == 2) 
		$display(" SUCCESS: Center IR fired for 2 times");
	else
		$error(" FAIL: Center IR does not fired for 2 times");

	cntrIR_n_count = 0;
  endtask

  task automatic check_fanfare(ref reg fanfare_go, ref reg [15:0] cmd);
	if(cmd[15:12] === 4'h5) begin
		wait(fanfare_go)
		assert(fanfare_go === 1)
			$display(" SUCCESS: Fanfare go is asserted ");
		else
			$error(" FAIL: Fanfare go is not asserted");
	end

  endtask


   //////////////////////////////////////////////////
   //////// Test with Tour command  /////////////////
   //////////////////////////////////////////////////

   task automatic num_moves_TL(ref logic [7:0] resp, ref resp_rdy);//, ref reg fanfare_go);
	
	for(int i = 1; i < 48; i++)
		@(posedge resp_rdy)
		if(resp === 8'h5A) 
			num_moves++;
		if(num_moves === 47) begin
			@(posedge resp_rdy);
			num_moves++;
			assert(resp === 8'hA5 && num_moves === 48) begin
				$display(" At Time: %t", $time);
				$display(" SUCCESS: Knights Tour is Completed ");
				$display(" SUCCESS: Number of moves made by Knight: %d", num_moves);
				$display(" SUCCESS: Response: %h", resp);
				end
			else
				$error(" FAIL: Knights Tour is incomplete");
		end
	

   endtask

  ///////////////////////////////////
  ////////// Common Tasks  //////////
  ///////////////////////////////////


  task automatic send_command(ref send_cmd, clk, ref reg [15:0] cmd, input [15:0] cmd_to_snd);
         cmd = cmd_to_snd;
	 $display(" Command sent: %h", cmd);
	 send_cmd = 1;
	 @(posedge clk);
	 send_cmd = 0;
  endtask 

  task automatic check4resp(ref logic clk, resp_rdy, [7:0] resp);
	fork
	 begin: timeout
          repeat (60000000) @(posedge clk);
          $display(" FAIL: Timed out waiting for response");
	  $stop();
         end
	 begin: check
          @(posedge resp_rdy)
	  assert(resp === 8'ha5) begin
		 disable timeout;
		 $display(" SUCCESS: Response received = %h", resp);
		end
          else 
		$error(" FAIL: Error at %t, Unintented response received", $time);
	 end
	join
  endtask

  task automatic wait4sig(ref logic clk, sig);
	fork
	 	begin: timeout
          		repeat (60000000) @(posedge clk);
          		$display(" FAIL: Timed out waiting for signal");
	  	$stop();
         	end
	 	begin: check
          		@(posedge sig) disable timeout;
	 	end
	join
  endtask
		
endpackage
