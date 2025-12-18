/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Baud rate is 19200 with 50MHz clock ? 2604 divider ? 12-bit
// tx sequence --> IDLE START D0 D1 D2 D3 D4 D5 D6 D7 STOP IDLE/START
// Transmitter sits idle till told to transmit. Then will shift out a 9-bit (start bit appended) register at the baud rate interval
// control signals --> init, shift, transmitting
// bit period = 1/baud = 2604
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module UART_tx (
    input rst_n,                  
    input clk,                    
    input trmt,                   // Transmit request signal
    input [7:0] tx_data,          // 8-bit data to be transmitted
    output reg TX,                
    output reg tx_done            // transmission completion
);

typedef enum reg {IDLE, TRANSMIT} UART_state_t; // State enumeration for UART transmission
UART_state_t state, nxt_state; 

logic [11:0] baud_cnt, baud_cnt_int;  // Baud rate counter and its internal version
logic init, shift, transmitting;      // Control signals for transmission process
logic [8:0] tx_shft_reg;              // 9-bit Shift register for transmission data {tx_data,start}
logic [3:0] bit_cnt, bit_cnt_int;     // Bit counter and its internal version
logic set_done, reset_done;           // Control signals for transmission completion


always_ff @(posedge clk, negedge rst_n)
    if(!rst_n) state <= IDLE;         
    else       state <= nxt_state;    


always_comb begin
    init = 0;                      
    set_done = 0;
    reset_done = 0;
    nxt_state = state;                

    case(state)
        IDLE: begin
            if(trmt) begin            // If transmit request is high
                init = 1'b1;          // Initiate transmission
                reset_done = 1'b1;   
                nxt_state = TRANSMIT;   
            end
        end
        TRANSMIT: begin
            if(bit_cnt == 4'd10) begin // After 10 bits transmitted
                set_done = 1'b1;      // Set done signal high
                nxt_state = IDLE;     
            end
        end
    endcase
end

// Baud rate counter logic
always_ff @(posedge clk, negedge rst_n)
    if(!rst_n) baud_cnt <= 0;         
    else baud_cnt <= baud_cnt_int;    

// Internal baud counter logic
always_comb
    case({init | shift, transmitting}) 
        00: baud_cnt_int = baud_cnt;     
        01: baud_cnt_int = baud_cnt + 1; 
	default: baud_cnt_int = 0;       // Reset baud count, condition --> 1?
    endcase

assign shift = (baud_cnt == 12'd2603) ? 1'b1 : 1'b0; // Shift condition for baud rate (2604 cycles)

// Shift register for transmitting data
always_ff @(posedge clk, negedge rst_n)
    if(!rst_n) tx_shft_reg <= '1;     
    else begin
        casex ({init, shift})          				
            2'b1?: tx_shft_reg <= {tx_data, 1'b0}; 		// Load data on init, (init has high priority)
            2'b01: tx_shft_reg <= {1'b1, tx_shft_reg[8:1]}; 	// Shift right
            2'b00: tx_shft_reg <= tx_shft_reg; 			// Maintain current value
        endcase
    end
assign TX = tx_shft_reg[0];           // Assign LSB of data to TX output

// Bit counter logic
always_ff @(posedge clk, negedge rst_n)
    if(!rst_n) bit_cnt <= 0;            // Reset bit counter
    else bit_cnt <= bit_cnt_int;        // Update bit counter

// Internal bit counter logic
always_comb
    case({init, shift})                 
        00: bit_cnt_int = bit_cnt;      
        01: bit_cnt_int = bit_cnt + 1;  // Increment count
        default: bit_cnt_int = 0;       // Reset bit count, condition --> 1? 
    endcase

// if bit_cnt reaches 10, stop transmitting
assign transmitting = (bit_cnt == 4'd10) ? 1'b0 : 1'b1;

// SR flip-flop for tx_done signal
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tx_done <= 1'b0;                // Reset tx_done signal
    else begin
        if (set_done)                   // Set signal for transmission completion
            tx_done <= 1'b1; 
        else if (reset_done)           // Reset signal for transmission
            tx_done <= 1'b0;  
    end
end

endmodule
