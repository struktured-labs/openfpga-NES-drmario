// Dr. Mario coprocessor STUB (milestone-2 scaffold for mapper 100).
// ---------------------------------------------------------------------------
// Purpose: prove the mapper-100 $5000-$51FF host window and the clk <-> clk_85_9
// clock-domain crossing end to end, BEFORE the real second 6502 + BoardEngine
// (LeafEval) is dropped in at milestone 3.
//
// This is a deliberate PORT MATCH for CoproDrMario.sv: identical ports and WIN
// parameter, so milestone 3 is a one-identifier swap in cart.sv
// (CoproStub -> CoproDrMario) plus adding the real sources under
// rtl/upstream/mappers/. It is NOT the AI. In place of the 6502 firmware it runs
// a tiny fixed-function FSM on clk_cpu (clk_85_9) that, on GO, reads the four
// pill-colour inputs the host wrote, computes a deterministic value, and writes
// best_col / best_orient + DONE back. That exercises exactly the two CDC paths
// the real block uses:
//   - bulk data + result/handshake : dual-clock TDP BRAM (dpram), same wrapper
//   - GO/reset pulse host -> copro  : 2FF synchroniser (copied from CoproDrMario.sv)
//
// Host register window at $5000-$51FF (open bus on stock MMC1), offset = prg_ain[8:0]:
//   $5000-$507F  W  scratch bytes 0..127   -> wram $0500+i   (bulk loopback path)
//   $5080-$5083  W  cA / cB / nA / nB      -> wram $824-$827  (copro inputs)
//   $5084        W  GO: clears DONE, pulses the copro FSM reset (re-runnable per pill)
//   $5084        R  DONE flag              <- wram $8FF; 1 = result ready
//   $5085        R  best_col               <- wram $834
//   $5086        R  best_orient            <- wram $835
// STUB result contract (deterministic, so a host-side test can predict it):
//   best_col    = (cA + cB + nA + nB) & 8'h07
//   best_orient = (cA ^ nB)           & 8'h03
module CoproStub #(parameter [6:0] WIN = 7'b0101_000) (   // WIN = prg_ain[15:9] window select
	input         clk,        // host/bridge clock (NES system clock ~21.47MHz)
	input         clk_cpu,    // coprocessor clock (clk85 ~85.9MHz)
	input         ce,         // M2 (game-CPU cycle enable) for host-side sampling
	input         enable,     // me[100]
	input  [15:0] prg_ain,
	input         prg_read,
	input         prg_write,
	input   [7:0] prg_din,
	output  [7:0] prg_dout,   // valid when copro_sel && prg_read (cart_top overrides)
	output        copro_sel   // host window hit (WIN)
);

assign copro_sel = enable && (prg_ain[15:9] == WIN);

// -------------------------------------------------------------- reset / GO handshake
// rst_cnt/parked live in the host (clk) domain; a GO write re-arms them. The pulse is
// carried into the fast domain by a 2FF synchroniser -- identical to CoproDrMario.sv.
reg   [4:0] rst_cnt = 5'h1F;    // parked in reset until first GO (host clk domain)
reg         parked  = 1'b1;
wire        cpu_rst_src = (rst_cnt != 0) || parked;
reg         rst_m = 1'b1, cpu_rst = 1'b1;
always @(posedge clk_cpu) begin rst_m <= cpu_rst_src; cpu_rst <= rst_m; end

// -------------------------------------------------------------- 4KB dual-clock TDP work RAM
// Port A: copro FSM (clk_cpu). Port B: host bridge (clk). Explicit dpram wrapper
// (altsyncram) -- behavioural TDP templates fail to infer on Quartus Std. q_* are
// synchronous reads with 1-cycle latency, which the FSM and the host both assume.
wire [7:0] ram_a_q, ram_b_q;
reg  [11:0] a_addr = 12'h0;
reg   [7:0] a_data = 8'h0;
reg         a_wr   = 1'b0;
reg  [11:0] hb_addr;
reg   [7:0] hb_din;
reg         hb_we;
dpram #(.widthad_a(12), .width_a(8)) wram (
	.clock_a  (clk_cpu),
	.address_a(a_addr),
	.data_a   (a_data),
	.wren_a   (a_wr),
	.q_a      (ram_a_q),
	.clock_b  (clk),
	.address_b(hb_addr),
	.data_b   (hb_din),
	.wren_b   (hb_we),
	.q_b      (ram_b_q)
);

// -------------------------------------------------------------- copro-side FSM (clk_cpu)
// Stand-in for the 6502 firmware. On release from reset: read the four inputs, compute a
// deterministic result, write best_col/best_orient, raise DONE, then halt until next GO.
// a_addr is registered here AND again by the dpram's synchronous read, so q_a is valid
// TWO cycles after the state that presents an address. Addresses are therefore pipelined
// (present $824, then $825, before the first capture) and each capture reads the address
// presented two states earlier.
localparam [3:0] S_IDLE=4'd0, S_A1=4'd1, S_CA=4'd2, S_CB=4'd3, S_NA=4'd4, S_NB=4'd5,
                 S_WCOL=4'd6, S_WORI=4'd7, S_WDONE=4'd8, S_HALT=4'd9;
reg  [3:0] st = S_IDLE;
reg  [7:0] cA, cB, nA, nB;

always @(posedge clk_cpu) begin
	a_wr <= 1'b0;
	if (cpu_rst) begin
		st <= S_IDLE;               // parked until GO releases reset
	end else begin
		case (st)
			S_IDLE:  begin a_addr <= 12'h824;                 st <= S_A1;    end // present cA addr
			S_A1:    begin a_addr <= 12'h825;                 st <= S_CA;    end // present cB addr (cA q not ready)
			S_CA:    begin cA <= ram_a_q; a_addr <= 12'h826;  st <= S_CB;    end // capture cA=mem[$824], present nA
			S_CB:    begin cB <= ram_a_q; a_addr <= 12'h827;  st <= S_NA;    end // capture cB=mem[$825], present nB
			S_NA:    begin nA <= ram_a_q;                     st <= S_NB;    end // capture nA=mem[$826]
			S_NB:    begin nB <= ram_a_q;                     st <= S_WCOL;  end // capture nB=mem[$827]
			S_WCOL:  begin a_addr <= 12'h834; a_data <= (cA + cB + nA + nB) & 8'h07; a_wr <= 1'b1; st <= S_WORI;  end
			S_WORI:  begin a_addr <= 12'h835; a_data <= (cA ^ nB)           & 8'h03; a_wr <= 1'b1; st <= S_WDONE; end
			S_WDONE: begin a_addr <= 12'h8FF; a_data <= 8'h01;                        a_wr <= 1'b1; st <= S_HALT;  end
			default: st <= S_HALT;      // S_HALT: idle until cpu_rst re-parks
		endcase
	end
end

// -------------------------------------------------------------- host bridge (port B control)
// Game-window offset -> copro folded RAM address (same fold as CoproDrMario.sv, so the
// host firmware/test is identical for the stub and the real block).
function [11:0] xlate(input [8:0] a);
	begin
		if (!a[8] && !a[7])      xlate = {5'b01010, a[6:0]};   // $5000-7F -> $0500+i (board)
		else if (!a[8] && a[7])
			case (a[6:0])
				7'h00: xlate = 12'h824;    // $5080 cA
				7'h01: xlate = 12'h825;    // $5081 cB
				7'h02: xlate = 12'h826;    // $5082 nA
				7'h03: xlate = 12'h827;    // $5083 nB
				7'h04: xlate = 12'h8FF;    // $5084 DONE
				7'h05: xlate = 12'h834;    // $5085 best_col
				7'h06: xlate = 12'h835;    // $5086 best_orient
				default: xlate = 12'h8FE;  // scratch
			endcase
		else                     xlate = 12'h8FE;              // $5100-$51FF scratch
	end
endfunction

always @(posedge clk) begin
	hb_we <= 1'b0;
	if (ce && prg_write && copro_sel) begin
		if (prg_ain[8:0] == 9'h084) begin
			// GO: clear DONE and (re)start the coprocessor
			hb_addr <= 12'h8FF; hb_din <= 8'h00; hb_we <= 1'b1;
			rst_cnt <= 5'h1F; parked <= 1'b0;
		end else begin
			hb_addr <= xlate(prg_ain[8:0]); hb_din <= prg_din; hb_we <= 1'b1;
		end
	end else begin
		hb_addr <= xlate(prg_ain[8:0]);    // idle: track read address (q_b valid next clk)
		if (rst_cnt != 0 && !parked) rst_cnt <= rst_cnt - 1'b1;
	end
end

assign prg_dout = ram_b_q;

endmodule
