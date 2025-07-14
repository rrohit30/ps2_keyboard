package PS2KeyboardInterface;

import Vector::*;
import RegFile::*;
import FIFO::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

// Parameters
typedef 11 TOTAL_BITS;
typedef Bit#(TOTAL_BITS) ShiftReg;
typedef Bit#(8) Byte;
typedef Bit#(12) Timer60;
typedef Bit#(8) Timer5;

// Timer constants
Integer timer_60usec_value_pp = 2950;
Integer timer_5usec_value_pp = 186;

// State definitions
typedef enum {
M1_rx_clk_h,
M1_rx_clk_l,
M1_rx_falling_edge_marker,
M1_rx_rising_edge_marker,
M1_tx_rising_edge_marker,
M1_tx_falling_edge_marker,
M1_tx_force_clk_l,
M1_tx_first_wait_clk_h,
M1_tx_first_wait_clk_l,
M1_tx_reset_timer,
M1_tx_wait_clk_h,
M1_tx_clk_h,
M1_tx_clk_l,
M1_tx_wait_keyboard_ack,
M1_tx_done_recovery,
M1_tx_error_no_keyboard_ack
}M1State deriving (Bits, Eq);

typedef enum {
M2_rx_data_ready_ack,
M2_rx_data_ready
}M2State deriving (Bits, Eq);

// Interface
interface PS2Interface;
method ActionValue#(Tuple5#(Bool, Bool, Bool, Byte, Byte)) readData;
method Action writeData(Byte txData);
method Bool txAck;
method Bool txError;
method Action reset;
endinterface

(* synthesize *)
module mkPS2KeyboardInterface(PS2Interface);

// Registers
Reg#(M1State) m1_state <- mkReg(M1_rx_clk_h);
Reg#(M2State) m2_state <- mkReg(M2_rx_data_ready_ack);
Reg#(Bit#(4)) bit_count <- mkReg(0);
Reg#(Timer60) timer_60 <- mkReg(0);
Reg#(Timer5) timer_5 <- mkReg(0);
Reg#(Bool) enable_timer_60 <- mkReg(False);
Reg#(Bool) enable_timer_5 <- mkReg(False);
Reg#(ShiftReg) q <- mkReg(0);

Reg#(Bool) rx_extended <- mkReg(False);
Reg#(Bool) rx_released <- mkReg(False);
Reg#(Bool) rx_data_ready <- mkReg(False);
Reg#(Byte) rx_scan_code <- mkReg(0);
Reg#(Byte) rx_ascii <- mkReg(0);

Reg#(Bool) hold_extended <- mkReg(False);
Reg#(Bool) hold_released <- mkReg(False);
Reg#(Bool) left_shift_key <- mkReg(False);
Reg#(Bool) right_shift_key <- mkReg(False);

Reg#(Bool) tx_error_flag <- mkReg(False);
Reg#(Bool) tx_ack <- mkReg(False);
Reg#(Byte) tx_data_reg <- mkReg(0);

// Derived signals
Bool rx_shifting_done = (bit_count == fromInteger(valueOf(TOTAL_BITS)));
Bool tx_shifting_done = (bit_count == fromInteger(valueOf(10)));
Bit#(9) shift_key_on = left_shift_key || right_shift_key;

// Timer 60 usec logic
rule count_timer_60 (enable_timer_60 && timer_60 < fromInteger(timer_60usec_value_pp - 1));
timer_60 <= timer_60 + 1;
endrule

rule reset_timer_60 (!enable_timer_60);
timer_60 <= 0;
endrule

// Timer 5 usec logic
rule count_timer_5 (enable_timer_5 && timer_5 < fromInteger(timer_5usec_value_pp - 1));
timer_5 <= timer_5 + 1;
endrule

rule reset_timer_5 (!enable_timer_5);
timer_5 <= 0;
endrule

// Bit counter logic
rule update_bit_count ((m1_state == M1_rx_falling_edge_marker) || (m1_state == M1_tx_rising_edge_marker));
bit_count <= bit_count + 1;
endrule

rule reset_bit_count (rx_shifting_done);
bit_count <= 0;
endrule

// Shift register update
rule shift_data ((m1_state == M1_rx_falling_edge_marker) || (m1_state == M1_tx_rising_edge_marker));
q <= { 1'b0, q[10:1] };
endrule

// Special scan codes
rule check_specials (rx_shifting_done);
if (q[8:1] == 8'hE0) hold_extended <= True;
else if (q[8:1] == 8'hF0) hold_released <= True;
else begin
hold_extended <= False;
hold_released <= False;
end
endrule

// Shift key tracking
rule shift_key_latch (rx_shifting_done);
if (q[8:1] == 8'h12) left_shift_key <= !hold_released;
else if (q[8:1] == 8'h59) right_shift_key <= !hold_released;
endrule

// ASCII decoding
function Byte getAscii(shift, Byte code);
case ({shift, code})
9'h11C: return 8'h41; // A
9'h132: return 8'h42; // B
9'h121: return 8'h43; // C
9'h123: return 8'h44; // D
9'h124: return 8'h45; // E
9'h12B: return 8'h46; // F
9'h134: return 8'h47; // G
9'h133: return 8'h48; // H
9'h143: return 8'h49; // I
9'h13B: return 8'h4A; // J
9'h142: return 8'h4B; // K
9'h14B: return 8'h4C; // L
9'h13A: return 8'h4D; // M
9'h131: return 8'h4E; // N
9'h144: return 8'h4F; // O
9'h14D: return 8'h50; // P
9'h115: return 8'h51; // Q
9'h12D: return 8'h52; // R
9'h11B: return 8'h53; // S
9'h12C: return 8'h54; // T
9'h13C: return 8'h55; // U
9'h12A: return 8'h56; // V
9'h11D: return 8'h57; // W
9'h122: return 8'h58; // X
9'h135: return 8'h59; // Y
9'h11A: return 8'h5A; // Z
default: return 8'h2E; // .
endcase
endfunction

// Output assignment when valid
rule output_ready (rx_shifting_done && !(q[8:1] == 8'hF0 || q[8:1] == 8'hE0));
rx_extended <= hold_extended;
rx_released <= hold_released;
rx_scan_code <= q[8:1];
rx_ascii <= getAscii(shift_key_on, q[8:1]);
rx_data_ready <= True;
endrule

// Interface methods
method ActionValue#(Tuple5#(Bool, Bool, Bool, Byte, Byte)) readData;
rx_data_ready <= False;
return tuple5(rx_extended, rx_released, shift_key_on, rx_scan_code, rx_ascii);
endmethod

method Action writeData(Byte d);
tx_data_reg <= d;
tx_ack <= True;
endmethod

method Bool txAck = tx_ack;
method Bool txError = tx_error_flag;

method Action reset;
m1_state <= M1_rx_clk_h;
m2_state <= M2_rx_data_ready_ack;
timer_60 <= 0;
timer_5 <= 0;
enable_timer_60 <= False;
enable_timer_5 <= False;
rx_extended <= False;
rx_released <= False;
rx_data_ready <= False;
rx_scan_code <= 0;
rx_ascii <= 0;
hold_extended <= False;
hold_released <= False;
left_shift_key <= False;
right_shift_key <= False;
tx_error_flag <= False;
tx_ack <= False;
bit_count <= 0;
q <= 0;
endmethod

endmodule

endpackage


