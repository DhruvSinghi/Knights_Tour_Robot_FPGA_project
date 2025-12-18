//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  Receiver monitors for falling edge of Start bit. Counts off ½ a bit time (1302 for start bit) and starts shifting
// (right shifting since LSB is first) data into a register and continues with full bit time (2604)
//  for remaining bits to sample the data in middle.
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


module UART_rx(
    input clk, rst_n,     //clock with active low reset
    input RX,         //Serial input for receiving data
    input clr_rdy,        // Clear ready signal to reset the rdy flag
    output reg [7:0] rx_data, // 8-bit received data output
    output reg rdy        // Ready signal indicating data is ready to be read
);

    typedef enum reg {IDLE, RECEIVE} UART_Rx_state_t;
    UART_Rx_state_t state, nxt_state;

    logic [11:0] baud_cnt, baud_cnt_int;    // Baud rate counter and its internal version
    logic start, shift, receiving;      // Control signals for reception process
    logic [8:0] rx_shift_reg;       // Shift register to hold received data
    logic [3:0] bit_cnt, bit_cnt_int;   // Bit counter and its internal version
    logic set_rdy, reset_rdy;       // Control signals to indicate ready flag
    logic RX_ff0, RX_ff1;           // Flip-flops for synchronizing RX signal

    // Synchronize the RX signal to eliminate metastability
    //RX (async signal) --> RX_ff0 --> RX_ff1 (synch)
    always_ff @(posedge clk, negedge rst_n) begin
        if(!rst_n) begin
            RX_ff0 <= 1;        //preset RX
            RX_ff1 <= 1;
        end
        else    begin
            RX_ff0 <= RX;
            RX_ff1 <= RX_ff0;
        end
    end

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            state <= IDLE;
        else
            state <= nxt_state;

    always_comb begin
        start = 0;
        set_rdy = 0;
        reset_rdy = 0;
        nxt_state = state;  // Default to hold the current state

        case(state)
            IDLE: begin
                if(!RX_ff1) begin
                    start = 1'b1;
                    reset_rdy = 1'b1;   //when start is 1, reset the ready flag
                    nxt_state = RECEIVE;
                end
            end
            RECEIVE:  begin
                if(bit_cnt == 4'd10) begin  // After receiving 10 bits
                    set_rdy = 1'b1;     // Signal that data is ready
                    nxt_state = IDLE;       // Return to IDLE state
                end
            end
        endcase
        if(clr_rdy) reset_rdy = 1'b1;        // Clear ready signal if requested
    end

    //baud counter
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            baud_cnt <= 12'd1301;   //0-1301 --> 1302
        else
            baud_cnt <= baud_cnt_int;

    always_comb
        case({start|shift, receiving})
            00: baud_cnt_int = baud_cnt;
            01: baud_cnt_int = baud_cnt - 1;
            default: baud_cnt_int = start ? 12'd1301 : 12'd2603;    //1?, 0-2063 --> 2064
        endcase

    assign shift = (baud_cnt == 12'd0) ? 1'b1 : 1'b0;   //assert shift, if the down counter reaches to 0

    //shift_reg for rx_data
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            rx_shift_reg <= '1; //asynch set on reset
        else begin
            case (shift)
                1'b0: rx_shift_reg <= rx_shift_reg;
                1'b1: rx_shift_reg <= {RX_ff1, rx_shift_reg[8:1]};
            endcase
        end

    assign rx_data = rx_shift_reg[7:0];     //start(0) is in -1, igonore it; stop bit(1) is in MSB

    //bit counter
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            bit_cnt <= 0;
        else
            bit_cnt <= bit_cnt_int;

    always_comb
        case({start,shift})
            2'b00: bit_cnt_int = bit_cnt;
            2'b01: bit_cnt_int = bit_cnt + 1;
            default: bit_cnt_int = 0;   //1?
        endcase

    //if bit count reaches 10, stop receiving
    assign receiving = (bit_cnt == 4'd10) ? 1'b0 : 1'b1;

    //SR FLOP for rdy signal
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdy <= 1'b0;
        else begin
            if (set_rdy)          // If set is high, set output to 1
                rdy <= 1'b1;
            else if (reset_rdy)   // If reset is high, reset output to 0
                rdy <= 1'b0;
        end
    end
endmodule