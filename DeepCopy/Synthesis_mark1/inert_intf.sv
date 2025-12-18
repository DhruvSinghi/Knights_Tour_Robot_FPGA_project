//////////////////////////////////////////////////////
// Interfaces with ST 6-axis inertial sensor.  In  //
// this application we only use Z-axis gyro for   //
// heading of robot.  Fusion correction comes    //
// from "gaurdrail" signals lftIR/rghtIR.       //
/////////////////////////////////////////////////
module inert_intf(clk,rst_n,strt_cal,cal_done,heading,rdy,lftIR,
                  rghtIR,SS_n,SCLK,MOSI,MISO,INT,moving);

  parameter FAST_SIM = 1;	// used to speed up simulation
  
  input clk, rst_n;
  input MISO;					// SPI input from inertial sensor
  input INT;					// goes high when measurement ready
  input strt_cal;				// initiate claibration of yaw readings
  input moving;					// Only integrate yaw when going
  input lftIR,rghtIR;			// gaurdrail sensors
  
  output cal_done;				// pulses high for 1 clock when calibration done
  output signed [11:0] heading;	// heading of robot.  000 = Orig dir 3FF = 90 CCW 7FF = 180 CCW
  output rdy;					// goes high for 1 clock when new outputs ready (from inertial_integrator)
  output SS_n,SCLK,MOSI;		// SPI outputs


  //////////////////////////////////
  // Declare any internal signal //
  ////////////////////////////////
  logic vld;		// vld yaw_rt provided to inertial_integrator
  logic snd;
  logic [15:0] cmd;
  logic [15:0] timer;
  logic timer_full;
  logic [15:0] resp;
  logic done;
  logic INT_ff1;
  logic INT_ff2;
  logic [7:0] store_yawH;
  logic [7:0] store_yawL;
  
  logic capture_yawH;
  logic capture_yawL;
  
  
  always_ff @(posedge clk, negedge rst_n)
  if(!rst_n) begin
   INT_ff1 <= 0;
   INT_ff2 <= 0;
  end
  else begin
   INT_ff1 <= INT;
   INT_ff2 <= INT_ff1;
  end


  always_ff @(posedge clk, negedge rst_n)
  if(!rst_n)
   store_yawH <= 0;
  else if(capture_yawH)
   store_yawH <= resp[7:0];

  always_ff @(posedge clk, negedge rst_n)
  if(!rst_n)
   store_yawL <= 0;
  else if(capture_yawL)
   store_yawL <= resp[7:0];

  always_ff @(posedge clk, negedge rst_n)
  if(!rst_n)
   timer <= 0;
  else
   timer <= timer + 5'b00001;
  
  assign timer_full = &timer;


 
 
  ////////////////////////////////////////////////////////////////////
  // Instantiate Angle Engine that takes in angular rate readings  //
  // and acceleration info and produces a heading reading         //
  /////////////////////////////////////////////////////////////////
  inertial_integrator #(FAST_SIM) iINT(.clk(clk), .rst_n(rst_n), .strt_cal(strt_cal),.vld(vld),
                           .rdy(rdy),.cal_done(cal_done), .yaw_rt({store_yawH,store_yawL}),.moving(moving),.lftIR(lftIR),
                           .rghtIR(rghtIR),.heading(heading));

  spi ispi(.clk(clk),.rst_n(rst_n),.miso(MISO),.snd(snd), .cmd(cmd),.resp(resp),.ss_n(SS_n),.mosi(MOSI),.sclk(SCLK),.done(done));

  typedef enum reg[2:0] {INIT1,INIT2,INIT3,INT_ff2_WAIT,CAP_YAW_L,CAP_YAW_H} state_t;
  state_t state, nxt_state;

  always_ff @(posedge clk, negedge rst_n)
  if(!rst_n)
   state <= INIT1;
  else
   state <= nxt_state;
  

  always_comb begin
  capture_yawL = 'h0;
  capture_yawH = 'h0;
  vld = 'h0;
  snd = 'h0;
  cmd = 'h0;
  nxt_state = state;

  case(state)
   default:begin
    cmd = 16'h0d02;
    if(timer_full) begin
	 snd = 1;
	 nxt_state = INIT2;
    end
   end
   INIT2:begin
    cmd = 16'h1160;
	if(done) begin
	 snd = 1;
	 nxt_state = INIT3;
	end
   end
   INIT3:begin
    cmd = 16'h1440;
	if(done) begin
	 snd = 1;
	 nxt_state = INT_ff2_WAIT;
	end
   end
   INT_ff2_WAIT:begin
    cmd = 16'hA6xx;
	if(INT_ff2 & done) begin 
	 snd = 1;
	 nxt_state = CAP_YAW_L;
	end
   end
   CAP_YAW_L:begin 
    cmd = 16'hA7xx;
	if(done) begin 
	 snd = 1;
	 capture_yawL = 1;
	 nxt_state = CAP_YAW_H;
	end
   end
   CAP_YAW_H:begin
    if(done) begin
	 capture_yawH = 1;
	 vld = 1;
	 nxt_state = INT_ff2_WAIT;
	end
   end
  endcase
 end
endmodule
	  