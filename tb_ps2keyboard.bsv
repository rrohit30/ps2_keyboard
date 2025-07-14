package tb_ps2keyboard;
import Vector::*;
import FIFOF::*;
import ClientServer::*;
import GetPut::*;
import StmtFSM::*;
import RegFile::*;
import Connectable::*;
import PS2KeyboardInterface::*;
 module mktb_ps2keyboard(Empty);
 let ps2ifc<-mkPS2KeyboardInterface;
 Reg#(Bool) ps2_clk<- mkReg(True);
 Reg#(Bool) ps2_data<- mkReg(True);
 rule drive_ps2_inputs;
 ps2ifc.ps2_clk<=ps2_clk;
 ps2ifc.ps2_data<=ps2_data;
 endrule
 function Bit#(1) odd_parity(Bit#(8) data);
 return ~(^data);
 endfunction
 function Action sendScancode(Bit#(8) code);
 action
 Bit#(11) packet ={1'b1,odd_parity(code),code,1'b0};
 for( Integer i=0;i<11;i=i+1) begin
    ps2_data<=packet[i];
    ps2_clk<=0;
    $display("Sent bit %0d=%b",i,packet[i]);
    $display("ps2_clk=LOW");
    $display("ps2_data= %b",ps2_data);
    $display("------------------");
    $display("TICK");
    $fflush(stdout);
    $display("Time: %0t",$time);
    ps2_clk<=1;
 end
 ps2_data<=1;
 ps2-clk<=1;
 endaction
 endfunction
 Stmt tb_seq=
     seq
        $display("sending scan code for key 'A'(8'h1C)");
        sendScancode(8'h1C);
        $display("waiting for output to stabilize");
        repeat(30) noAction;
        $display("Checking DUT Outputs..");
        $display("Scan code : %x",ps2ifc.rx_scancode);
        $display("ASCII : %c ", ps2ifc.rx_ascii);
        $display("Extended? : %b ", ps2ifc.rx_extended);
        $display("Released? : %b ", ps2ifc.rx_released);
        $display("Shift? : %b ", ps2ifc.rx_shift_key_on);
        $display("Data Ready : %b ", ps2ifc.rx_data_ready);
        $finish;
      endseq;
      
      mkAutoFSM(tb_seq);
endmodule
endpackage
        
     
 
