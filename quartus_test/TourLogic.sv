module TourLogic(clk,rst_n,x_start,y_start,go,done,indx,move);

    input clk,rst_n;                // 50MHz clock and active low asynch reset
    input [2:0] x_start, y_start;   // starting position on 5x5 board
    input go;                       // initiate calculation of solution
    input [4:0] indx;               // used to specify index of move to read out
    output logic done;          // pulses high for 1 clock when solution complete
    output [7:0] move;          // the move addressed by indx (1 of 24 moves)

    ////////////////////////////////////////
    // Declare needed internal registers //
    //////////////////////////////////////

    //  << some internal registers to consider: >>
    //  << These match the variables used in knightsTourSM.pl >>
    reg board[0:4][0:4];                // keeps track if position visited
    reg [7:0] last_move[0:23];      // last move tried from this spot
    reg [7:0] poss_moves[0:23];     // stores possible moves from this position as 8-bit one hot
    reg [7:0] move_try;             // one hot encoding of move we will try next
    reg [4:0] move_num;             // keeps track of move we are on
    reg [2:0] xx,yy;                    // current x & y position

    //  << 2-D array of 5-bit vectors that keep track of where on the board the knight
    //     has visited.  Will be reduced to 1-bit boolean after debug phase >>
    //  << 1-D array (of size 24) to keep track of last move taken from each move index >>
    //  << 1-D array (of size 24) to keep track of possible moves from each move index >>
    //  << move_try ... not sure you need this.  I had this to hold move I would try next >>
    // << move number...when you have moved 24 times you are done.  Decrement when backing up >>
    //  << xx, yy couple of 3-bit vectors that represent the current x/y coordinates of the knight>>

    //  << below I am giving you an implementation of the one of the register structures you have >>
    //  << to infer (board[][]).  You need to implement the rest, and the controlling SM >>

    logic zero;
    logic init;
    logic update_position;
    logic [2:0] nxt_xx, nxt_yy;
    logic backup;
    logic try;
    logic try_next;

    ///////////////////////////////////////////////////
    // The board memory structure keeps track of where
    // the knight has already visited.  Initially this
    // should be a 5x5 array of 5-bit numbers to store
    // the move number (helpful for debug).  Later it
    // can be reduced to a single bit (visited or not)
    ////////////////////////////////////////////////
    always_ff @(posedge clk)
        if (zero)
            board <= '{'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0},'{0,0,0,0,0}};
        else if (init)
            board[x_start][y_start] <= 'h1; // mark starting position
        else if (update_position)
            board[nxt_xx][nxt_yy] <= 'h1;   // mark as visited
        else if (backup)
            board[xx][yy] <= 'h0;           // mark as unvisited

    // << Your magic occurs here >>
    
    
    assign nxt_xx = xx + off_x(move_try);
    assign nxt_yy = yy + off_y(move_try);
                    
    typedef enum logic [2:0] { IDLE, INIT, POSSIBLE, MAKE_MOVE, BACK_UP } state_t;
    state_t state, nxt_state;

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;

    always_comb begin
        nxt_state = state;
        try = 0;
        try_next = 0;
        backup = 0;
        init = 0;
        update_position = 0;
        zero = 0;
        done = 1'b0;

        case(state)
            INIT: begin
                init = 1;
                nxt_state = POSSIBLE;
            end

            POSSIBLE: begin
                try = 1;
                nxt_state = MAKE_MOVE;
            end

            MAKE_MOVE: begin
                if(move_num == 5'd24) begin
                    done = 1'b1;
                    nxt_state = IDLE;
                end
                else begin
                    
                    if((poss_moves[move_num] & move_try) && !board[xx + $signed(off_x(move_try))][yy + $signed(off_y(move_try))]) begin
                        //$display(
                        update_position = 1;
                        nxt_state = POSSIBLE;
                    end
                    else if(move_try != 8'h80) begin
                        try_next = 1;
                        nxt_state = MAKE_MOVE;
                    end
                    else begin
                        backup = 1;
                        nxt_state = BACK_UP;
                    end
                end
            end

            BACK_UP: begin
                    if(last_move[move_num] != 8'h80)
                        nxt_state = MAKE_MOVE;
                    else
                        backup = 1;
            end

            default: // default case is IDLE
                if(go) begin
                    zero = 1;
                    nxt_state = INIT;
                end
        endcase

    end

    // up and down counter to update move number
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            move_num <= '0;
        else if(update_position)
            move_num <= move_num + 1; //due to non-blocking statements, we'll get input at posedge of clk, and output is assigned at next posedge of clk
        else if(backup)
            move_num <= move_num - 1;

    assign move = last_move[indx];

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            last_move <= '{default: 8'h0};
        else if(update_position)
            last_move[move_num] <= move_try;

    always_ff @(posedge clk, negedge rst_n)
    if(!rst_n)
        poss_moves <= '{default: 8'h0};
    else if(try)
        poss_moves[move_num] <= calc_poss(xx,yy);

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            move_try <= 'h0;
        else if(try)
            move_try <= 8'h1;
        else if(try_next)
            move_try <= move_try << 1;
        else if(backup)
            move_try <= last_move[move_num -1] << 1;

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n) begin
            xx <= '0;
            yy <= '0;
        end
        else if(init) begin
            xx <= x_start;
            yy <= y_start;
        end
        else if(update_position) begin
            xx <= xx + $signed(off_x(move_try));
            yy <= yy + $signed(off_y(move_try));
        end
        else if(backup) begin
            xx <= xx - $signed(off_x(last_move[move_num - 1]));
            yy <= yy - $signed(off_y(last_move[move_num - 1]));
        end

    function [7:0] calc_poss(input [2:0] xpos,ypos);
    ///////////////////////////////////////////////////
    // Consider writing a function that returns a packed byte of
    // all the possible moves (at least in bound) moves given
    // coordinates of Knight.
    /////////////////////////////////////////////////////

        calc_poss[0] = (xpos < 3'd4 && ypos < 3'd3);
        calc_poss[1] = (xpos > 3'd0 && ypos < 3'd3);
        calc_poss[2] = (xpos > 3'd1 && ypos < 3'd4);
        calc_poss[3] = (xpos > 3'd1 && ypos > 3'd0);
        calc_poss[4] = (xpos > 3'd0 && ypos > 3'd1);
        calc_poss[5] = (xpos < 3'd4 && ypos > 3'd1);
        calc_poss[6] = (xpos < 3'd3 && ypos > 3'd0);
        calc_poss[7] = (xpos < 3'd3 && ypos < 3'd4);

    endfunction

    function signed [2:0] off_x(input [7:0] try);
    ///////////////////////////////////////////////////
    // Consider writing a function that returns a the x-offset
    // the Knight will move given the encoding of the move you
    // are going to try.  Can also be useful when backing up
    // by passing in last move you did try, and subtracting
    // the resulting offset from xx
    /////////////////////////////////////////////////////
        off_x = (try == 8'h01 || try == 8'h20) ? 3'd1 :
                (try == 8'h40 || try == 8'h80) ? 3'd2:
                (try == 8'h02 || try == 8'h10) ? -3'sd1 :
                (try == 8'h04 || try == 8'h08) ? -3'sd2 :
                'x;
    /*  if(try == 8'h01 || try == 8'h20)    off_x = 3'b001; // +1
        else if(try == 8'h40 || try == 8'h80)   off_x = 3'b010; // +2
        else if(try == 8'h02 || try == 8'h10)   off_x = 3'b111; // -1
        else if(try == 8'h04 || try == 8'h08)   off_x = 3'b110; // +2
    */
    endfunction

    function signed [2:0] off_y(input [7:0] try);
    ///////////////////////////////////////////////////
    // Consider writing a function that returns a the y-offset
    // the Knight will move given the encoding of the move you
    // are going to try.  Can also be useful when backing up
    // by passing in last move you did try, and subtracting
    // the resulting offset from yy
    /////////////////////////////////////////////////////
        off_y = (try == 8'h01 || try == 8'h02) ? 3'd2 :
                (try == 8'h04 || try == 8'h80) ? 3'd1 :
                (try == 8'h08 || try == 8'h40) ? -3'sd1 :	//signed decimal
                (try == 8'h10 || try == 8'h20) ? -3'sd2 :
                'x;
    endfunction

    /********************************
    hex values
    0 --> 01
    1 --> 02
    2 --> 04
    3 --> 08
    4 --> 10
    5 --> 20
    6 --> 40
    7 --> 80
    *********************************/

endmodule


