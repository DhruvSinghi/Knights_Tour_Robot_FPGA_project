module UART_wrapper (
    input clk, rst_n,
    input RX,
    input clr_cmd_rdy,
    input trmt,
    input [7:0] resp,
    output logic cmd_rdy,
    output logic [15:0] cmd,
    output logic TX,
    output logic tx_done
);

    typedef enum reg { MSB, LSB } wrapper_state_t;
    wrapper_state_t state, nxt_state;

    logic rx_rdy;
    logic [7:0] rx_data;
    logic clr_rdy;
    logic [7:0] MSB_cmd;  // to hold MSB of command
    logic capture_MSB;  // to hold MSB
    logic set_cmd_rdy;
    logic store_high;   //reset cmd_rdy when storing MSB

    UART iUART0(.clk(clk),.rst_n(rst_n),.rx_rdy(rx_rdy),.clr_rx_rdy(clr_rdy),.rx_data(rx_data),.RX(RX),.TX(TX),.trmt(trmt),.tx_data(resp),.tx_done(tx_done));

    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            state <= MSB;
        else
            state <= nxt_state;

    always_comb begin
        store_high = 0;
        set_cmd_rdy = 0;
        clr_rdy = 0;
        capture_MSB = 0;
        nxt_state = state;

        case(state)
            LSB: begin
                if(rx_rdy) begin
                    clr_rdy = 1'b1;
                    set_cmd_rdy = 1'b1;
                    nxt_state =  MSB;
                end
            end
            default: begin      //default case ==> MSB
                if(rx_rdy) begin
                    capture_MSB = 1'b1;
                    clr_rdy = 1'b1;
                    store_high = 1'b1; //reset cmd_rdy
                    nxt_state = LSB;
                end
            end
        endcase
    end

    // to hold MSB of cmd from UART
    always_ff @(posedge clk, negedge rst_n)
        if(!rst_n)
            MSB_cmd <= 1'b0;
        else if(capture_MSB)
            MSB_cmd <= rx_data;
    // the design is based on conditionally enabled flops

    assign cmd = { MSB_cmd, rx_data };

    // SR flip-flop for cmd_rdy signal
    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            cmd_rdy <= 1'b0;                // Reset cmd_rdy signal
        else begin
            if (set_cmd_rdy)
                cmd_rdy <= 1'b1;
            else if (store_high || clr_cmd_rdy)
                cmd_rdy <= 1'b0;
        end
    end
endmodule