module cmd_proc
    #(parameter FAST_SIM = 1) //FAST SIM default to 1 for simulation purpose
    (
    input clk,
    input rst_n,
    input [15:0] cmd,
    input cmd_rdy,
    input [11:0] heading,
    input heading_rdy,
    input cal_done,
    input lftIR,
    input cntrIR,
    input rghtIR,

    output reg clr_cmd_rdy,
    output reg send_resp,
    output reg tour_go,
    output reg strt_cal,
    output reg moving,
    output reg fanfare_go,
    output reg signed[9:0] frwrd,
    output logic signed [11:0] error
);

    //SM outputs to control frwrd register
    logic clr_frwrd;
    logic inc_frwrd;
    logic dec_frwrd;

    //Opcodes
    localparam TOUR_GO = 4'b0110;
    localparam CALIBRATE = 4'b0010;
    localparam MOVE = 4'b0100;
    localparam MOVE_FANFARE = 4'b0101;

    //frwrd reg datapath
    wire en;
    wire zero;
    wire max_spd;
    logic signed [9:0] frwrd_update;

    generate if (FAST_SIM)
        assign frwrd_update = ((inc_frwrd) ? 10'h020 : 10'h3c0);    //FAST SIM 1 if incrementing increment at 20 or else it is -2*(20)
    else
        assign frwrd_update = ((inc_frwrd) ? 10'h003 : 10'h3fa);    //FAST SIM 0 if incrementing increment at 3 or else it is -2*(3)
    endgenerate

    //forward register
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            frwrd <= 0;
        else if(clr_frwrd)
            frwrd <= 0;
        else if(en)
            frwrd <= $signed(frwrd) + $signed(frwrd_update);

    assign zero = ~(|frwrd);            ///zero if all bits 0
    assign max_spd = &frwrd[9:8];       ///max speed if bit 9 and 8 are 1

    //enable frwrd update on heading rdy, allow decrement if not zero and allow increment if not at max speed
    assign en = ((~max_spd) || dec_frwrd) & ((~zero) || inc_frwrd) & heading_rdy;

    //counting squares
    reg move_cmd;
    wire move_done;
    reg [3:0] counted_lines;
    reg [2:0] squares_to_count;
    reg rise_edge_detect;

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            counted_lines <= 0;
        else if(move_cmd)
            counted_lines <= 0;
        else if(rise_edge_detect)
            counted_lines <= counted_lines + 1;

    //cntr IR is asynch signal, double flopped for metastability
    reg ff1,ff2,ff3;
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n) begin
            ff1 <= 0;
            ff2 <= 0;
            ff3 <= 0;
        end
        else begin
            ff1 <= cntrIR;
            ff2 <= ff1;
            ff3 <= ff2;
        end

    //edge detection logic
    assign rise_edge_detect = ff2 & (~ff3);

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            squares_to_count <= 0;
        else if(move_cmd)
            squares_to_count <= cmd[2:0];

    //1 square is moved when 2 lines are detected ( therefore square*2 === lines when move done)
    assign move_done = moving ? ({squares_to_count,1'b0} == counted_lines) : 1'b0;

    //error term calculation
    //desired heading calculated from cmd: the anatomy is to promote 4 bits and append f if not zero, based on encoding
    reg [11:0] desired_heading;
    wire [11:0] err_nudge;
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            desired_heading <= 0;
        else if(move_cmd)
            desired_heading <= (cmd[11:4] == 0) ? ({cmd[11:4],4'h0}) : ({cmd[11:4],4'hf});

    //to nudge the bot error term if it is crossing the guard rails
    generate if (FAST_SIM)
        assign err_nudge = ((lftIR) ? 12'h1ff : ((rghtIR) ? 12'he00 : 12'h0));
    else
        assign err_nudge = ((lftIR) ? 12'h05f : ((rghtIR) ? 12'hfa1 : 12'h0));
    endgenerate

    assign error = heading + err_nudge - desired_heading;

    typedef enum reg [2:0] {IDLE,CAL,MOV_CMD,RAMP_UP,RAMP_DOWN} state_t;
    state_t state, nxt_state;

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;

    always_comb begin
        clr_frwrd = 'h0;
        clr_cmd_rdy = 'h0;
        inc_frwrd = 0;
        dec_frwrd = 0;
        move_cmd = 0;
        tour_go = 0;
        strt_cal = 0;
        moving = 0;
        send_resp = 0;
        fanfare_go = 0;
        nxt_state = state;

        case (state)
            default: begin
                if(cmd_rdy) begin   // wait for cmd
                    clr_cmd_rdy = 1;
                    clr_frwrd = 1;
                    if(cmd[15:12] == TOUR_GO) begin //if tour_go cmd just make tour go and come to same state
                        tour_go = 1;
                    end
                    else if (cmd[15:12] == CALIBRATE) begin //calibration command
                        strt_cal = 1;
                        nxt_state = CAL;
                    end
                    else if(cmd[15:12] == MOVE_FANFARE || cmd[15:12] == MOVE) begin //move with fanfare or normal move command
                        move_cmd = 1;
                        nxt_state = MOV_CMD;
                    end
                end
            end

            CAL : begin //wait for cal done and return to idle when it comes
                clr_frwrd = 1;
                if(cal_done) begin
                    send_resp = 1;
                    nxt_state = IDLE;
                end
            end

            MOV_CMD : begin  // wait for PID to reduce the error by spinning at one place(this is moving phase)
                moving = 1;
                clr_frwrd = 1;
                if ((error < $signed(12'h02c)) && (error > $signed(-12'h02c))) begin
                    nxt_state = RAMP_UP;
                end
            end

            RAMP_UP : begin //( now desired heading and heading match move the required number of squares
                moving = 1;
                inc_frwrd = 1;
                if(move_done) begin
                    nxt_state = RAMP_DOWN;
                end
            end

            RAMP_DOWN : begin //slow down to stop at center of the square
                moving = 1;
                dec_frwrd = 1;
                if(cmd[15:12] == 4'b0101)
                    fanfare_go = 1;
                    if(zero) begin
                        send_resp = 1;
                        nxt_state = IDLE;
                    end
            end
        endcase
    end
endmodule

