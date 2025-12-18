module spi(
input clk,
input rst_n,
input miso,
input snd,
input [15:0] cmd,
output [15:0] resp,
output reg ss_n,
output mosi,
output sclk,
output reg done
);
reg init;
reg ld_sclk;
reg set_done;
reg [4:0] sclk_div;
reg [4:0] bit_cntr;
reg [15:0] shift_reg;
wire shift;
wire full;
wire done16;

//sclk generation block, it is 5 bit as it is 1/2^5 of clk
always_ff @(posedge clk,negedge rst_n)
if(!rst_n)
sclk_div <= '1; //sclk is normally high
else if(ld_sclk)
sclk_div <= 5'b10111; //if set to this value sclk will becomes 0 after required front_porch of 9 clks
else
sclk_div <= sclk_div + 1; //normally sclk increments

assign sclk = sclk_div[4]; //MSB of div is sclk, rises or falls on every 32 clocks
//assign shift = sclk_div[4] & sclk_div[0] & (~|(sclk_div[3:1])); //we shift on two clocks after sclk rise i.e 10001
assign shift = (sclk_div == 5'b10001);
assign full = &sclk_div[4:0]; //used for preventing sclk fall during back_porch

//bit counter to count 16 bits 
always_ff@(posedge clk,negedge rst_n)
if(!rst_n)
bit_cntr[4:0] <= 'b0;
else if(init)
bit_cntr[4:0] <= 5'b00000;
else if(shift)
bit_cntr[4:0] <= bit_cntr + 1;

assign done16 = bit_cntr[4];

//main block: shifter register of spi : on every shift shifts out mosi; gets in miso
always_ff@(posedge clk,negedge rst_n)
if(!rst_n)
 shift_reg <= 16'h0000;
else if(init)
 shift_reg[15:0] <= cmd[15:0];
else if(shift)
 shift_reg[15:0] <= {shift_reg[14:0],miso};

assign mosi = shift_reg[15];
assign resp = shift_reg[15:0]; //at end of the transaction data received is available here

//done signal controlled using RS flop to register SM outputs
always_ff @(posedge clk,negedge rst_n)
if(!rst_n)
done <= 0;
else if(init)
done <= 0;
else if(set_done)
done <= 1;

//Serf select; normally high; goes low in beginning of transaction to select the serf
always_ff @(posedge clk,negedge rst_n)
if(!rst_n)
ss_n <= 1;
else if(init)
ss_n <= 0;
else if(set_done)
ss_n <= 1;

//SM logic begins
typedef enum reg [1:0] {IDLE,TRANSMITTING,BACK_PORCH} state_t;
state_t state,nxt_state;

//state transition flip flop
always @(posedge clk,negedge rst_n)
if(!rst_n)
state <= IDLE;
else
state <= nxt_state;

always_comb begin
init = 'h0; //default SM outputs to prevent latches
set_done = 'h0;
ld_sclk = 'h0;
nxt_state = state; //most of the time state remains same
 
case(state)

IDLE: 
begin ld_sclk = 1; //keep asserting ld_sclk till snd_cmd is received
if(snd)  begin
         init = 1;
         nxt_state = TRANSMITTING;
end
end
TRANSMITTING: //wait for 16 bits to be exchanged
if(done16)
         nxt_state = BACK_PORCH; //handle backporch
BACK_PORCH:
if(full) begin //as soon as sclk_div is maximum assert ld_clk to prevent its fall
         ld_sclk = 1;
         set_done = 1; //set done signal to deassert serf_select and indicate completion
         nxt_state = IDLE;
end
endcase
end

endmodule



