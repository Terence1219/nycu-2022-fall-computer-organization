module SP(
	// INPUT SIGNAL
	clk,
	rst_n,
	in_valid,
	inst,
	mem_dout,
	// OUTPUT SIGNAL
	out_valid,
	inst_addr,
	mem_wen,
	mem_addr,
	mem_din
);

//------------------------------------------------------------------------
//   INPUT AND OUTPUT DECLARATION                         
//------------------------------------------------------------------------

input                    clk, rst_n, in_valid;
input             [31:0] inst;
input  signed     [31:0] mem_dout;
output reg               out_valid;
output reg        [31:0] inst_addr;
output reg               mem_wen;
output reg        [11:0] mem_addr;
output reg signed [31:0] mem_din;

//------------------------------------------------------------------------
//   DECLARATION
//------------------------------------------------------------------------

// REGISTER FILE, DO NOT EDIT THE NAME.
reg	signed [31:0] r [0:31]; 

localparam S_IDLE = 0;
localparam S_IN = 1;
localparam S_EXE = 2;
localparam S_OUT = 3;
integer i;

reg signed[31:0] rs_now, rt_now, rd_now;
reg [1:0] current_state, next_state;
reg [5:0] opcode;
reg [4:0] rs;
reg [4:0] rt;
reg [4:0] rd;
reg [4:0] shamt;
reg [5:0] funct;
reg [15:0] imm;
reg [3:0] delay;
reg signed [31:0] SEimm;
reg [31:0] ZEimm;
reg signed [31:0] ALU_output;
reg signed[31:0] rs_store, rt_store, rd_store;
//------------------------------------------------------------------------
//   DESIGN
//------------------------------------------------------------------------
always @(posedge clk, negedge rst_n)
begin
	if(rst_n == 0) //reset all regs
	begin
		current_state <= S_IDLE;
		inst_addr <= 0;
		out_valid <= 0;
		delay <= 0;
		mem_wen <= 1;
		mem_addr <= 0;
		mem_din <= 0;
		for (i=0;i<32;i=i+1)
		begin
			r[i] <= 0;
		end
	end
	else  //move to next state
	begin
		current_state <= next_state;
	end
end

always @(posedge clk) //4 cycles between in and out
begin
	delay <= delay << 1;
	delay[0] <= in_valid;
	out_valid <= delay[3];
end

always @(*) //decide next state
begin
	case(current_state)
		S_IDLE:
			if(in_valid)
				next_state = S_IN; //go to in state if in is valid
			else
				next_state = S_IDLE;
		S_IN:
			if(in_valid)
				next_state = S_IN;
			else
				next_state = S_EXE; //go to exe state if input has finished
		S_EXE:
			if(delay[3])
				next_state = S_OUT; //go to out state if out will be valid next cycle
			else
				next_state = S_EXE;
		S_OUT:
		begin
			next_state = S_IDLE; //wait for new instruction
			inst_addr = inst_addr + 4; //next instruction addr
		end
		default:
			next_state = S_IDLE;
	endcase
end

always @(posedge clk)
begin
	if(next_state == S_IN)
	begin
		opcode = inst[31:26]; //instruction decode
		rs = inst[25:21];
		rt = inst[20:16];
		rd = inst[15:11];
		shamt = inst[10:6];
		funct = inst[5:0];
		imm = inst[15:0];
		ZEimm = {16'b0, inst[15:0]};
		SEimm = {{16{inst[15]}}, inst[15:0]};
		rs_now = r[rs];
		rt_now = r[rt];
		rd_now = r[rd];

		case(opcode) //use opcode to decide what to do
			6'b000000: // r type
			begin
				case(funct)
					6'b000000: //and
						ALU_output <= rs_now & rt_now;
					6'b000001: //or
						ALU_output <= rs_now | rt_now;
					6'b000010: //add
						ALU_output <= rs_now + rt_now;
					6'b000011: //sub
						ALU_output <= rs_now - rt_now;
					6'b000100: //slt
						ALU_output <= rs_now < rt_now;
					6'b000101: //sll
						ALU_output <= rs_now << shamt;
					6'b000110: //nor
						ALU_output <= ~(rs_now | rt_now);
				endcase
			end // i type
			6'b000001: //andi
				ALU_output <= rs_now & ZEimm;
			6'b000010: //ori
				ALU_output <= rs_now | ZEimm;
			6'b000011: //addi
				ALU_output <= rs_now + SEimm;
			6'b000100: //subi
				ALU_output <= rs_now - SEimm;
			6'b000101: //lw
				ALU_output <= rs_now + SEimm;
			6'b000110: //sw
				ALU_output <= rs_now + SEimm;
			6'b000111: //beq
			begin
				if(rs_now == rt_now)
					ALU_output <= inst_addr + {{14{SEimm[15]}}, SEimm[15:0]}*4;
			end
			6'b001000: //bne
			begin
				if(rs_now != rt_now)
					ALU_output <= inst_addr + {{14{SEimm[15]}}, SEimm[15:0]}*4;
			end
			6'b001001: //lui
				ALU_output <= {imm, 16'h0000};
		endcase
	end
	else if(next_state == S_EXE)
	begin
		case(opcode)
			6'b000000: //r type
				rd_store <= ALU_output;
			6'b000001:
				rt_store <= ALU_output;
			6'b000010:
				rt_store <= ALU_output;
			6'b000011:
				rt_store <= ALU_output;
			6'b000100:
				rt_store <= ALU_output;
			6'b000101: //lw
			begin
				mem_wen <= 1;
				mem_addr <= ALU_output;
				rt_store <= mem_dout;
			end
			6'b000110: //sw
			begin
				mem_wen <= 0;
				mem_addr <= ALU_output;
				mem_din <= rt_now;
			end
			6'b000111: //beq
			begin
				if(rs_now == rt_now)
					inst_addr <= ALU_output;
			end
			6'b001000: //bne
			begin
				if(rs_now != rt_now)
					inst_addr <= ALU_output;
			end
			6'b001001:
				rt_store <= ALU_output;
		endcase
	end
	else if(next_state == S_OUT)
	begin
		case(opcode)
			6'b000000: //r type
				r[rd] <= rd_store;
			6'b000001: //andi
				r[rt] <= rt_store;
			6'b000010: //ori
				r[rt] <= rt_store;			
			6'b000011: //addi
				r[rt] <= rt_store;
			6'b000100: //subi
				r[rt] <= rt_store;
			6'b000101: //lw
				r[rt] <= rt_store;
			6'b001001: //lui
				r[rt] <= rt_store;
		endcase
	end
end
endmodule