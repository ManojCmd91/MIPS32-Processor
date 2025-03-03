module pipe_MIPS32(clk1, clk2);
input clk1,clk2; //Two-phase clock
reg [31:0] PC,IF_ID_IR,IF_ID_NPC;
reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
reg [2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
reg EX_MEM_cond;
reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;
reg [31:0] Reg [0:31]; // REGISTER BANK (32X32)
reg [31:0] Mem [0:1023]; //1024X32 MEMORY
parameter ADD=6'b000000, SUB=6'b000001, AND=6'b000010, OR=6'b000011,SLT=6'b000100, 
	  MUL=6'b000101, HLT=6'b111111, LW=6'b001000,SW=6'b001001, ADDI=6'b001010, 
	  SUBI=6'b001011, SLTI=6'b001100,BNEQZ=6'b001101, BEQZ=6'b001110;
parameter RR_ALU=3'b000, RM_ALU=3'b001, LOAD=3'b010, STORE=3'b011, BRANCH=3'b100, HALT=3'b101;
reg HALTED; //Set after HLT instruction is completed (in wb stage)
reg TAKEN_BRANCH; //Required to disable instructions after branch 

always @(posedge clk1) //IF STAGE 
	if (HALTED ==0) 
	begin 
	if (((EX_MEM_IR[31:26] == BEQZ) && (EX_MEM_cond == 1)) ||
		((EX_MEM_IR[31:26] ==BNEQZ) && (EX_MEM_cond == 0)))
	 begin 
		IF_ID_IR <= #2 Mem[EX_MEM_ALUOut];
		TAKEN_BRANCH <= #2 1'b1;
		IF_ID_NPC <= #2 EX_MEM_ALUOut +1;
		PC <= #2 EX_MEM_ALUOut +1;
	 end 
	else
	 begin
		IF_ID_IR <= #2 Mem[PC];
		IF_ID_NPC <= #2 PC+1;
		PC <= #2 PC+1;
	 end
	end
always @(posedge clk2) 	//ID STAGE
	if (HALTED == 0)
	 begin 
		if (IF_ID_IR[25:21] ==5'b00000) ID_EX_A <= 0;
		else ID_EX_A <= #2 Reg[IF_ID_IR[25:21]]; // "rs"
		if (IF_ID_IR[20:16] == 5'b00000) ID_EX_B <=0;
		else ID_EX_B <= #2 Reg[IF_ID_IR[20:16]]; //"rt"
		
		ID_EX_NPC <= #2 IF_ID_NPC;
		ID_EX_IR <= #2 IF_ID_IR;
		ID_EX_Imm <= #2 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}};
		case (IF_ID_IR[31:26])
			ADD,SUB,AND,OR,SLT,MUL: ID_EX_type <= #2 RR_ALU;
			ADDI,SUBI,SLTI: ID_EX_type <= #2 RM_ALU;
			LW: ID_EX_type <= #2 LOAD;
			SW: ID_EX_type <= #2 STORE;
			BNEQZ,BEQZ: ID_EX_type <= #2 BRANCH;
			HLT: ID_EX_type <= #2 HALT;
			default: ID_EX_type <= #2 HALT; //INVALID OPCODE
		endcase
	end
always @(posedge clk1) //EX STAGE
	if (HALTED == 0)
	begin 
		EX_MEM_type <= #2 ID_EX_type;
		EX_MEM_IR <= #2 ID_EX_IR;
		TAKEN_BRANCH <= #2 0;
		case (ID_EX_type)
			RR_ALU: begin
					case (ID_EX_IR[31:26]) //OPCODE
						ADD: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
						SUB: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
						AND: EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
						OR: EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
						SLT: EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_B;
						MUL: EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
						default: EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
					endcase
				end
			RM_ALU: begin 
					case(ID_EX_IR[31:26]) //OPCODE
						ADDI: EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
						SUBI: EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
						SLTI: EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_Imm;
						default: EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
					endcase
				end
			LOAD, STORE:
				begin 
				  EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
				  EX_MEM_B <= #2 ID_EX_B;
				end
			BRANCH: 
				begin
				  EX_MEM_ALUOut <= #2 ID_EX_NPC +ID_EX_Imm;
				  EX_MEM_cond <= #2 (ID_EX_A == 0);
				end
		endcase
	end
always @(posedge clk2) // MEM STAGE
 if (HALTED == 0)
 begin 
	MEM_WB_type <= #2 EX_MEM_type;
	MEM_WB_IR <= #2 EX_MEM_IR;
	case (EX_MEM_type)
		RR_ALU, RM_ALU:
			MEM_WB_ALUOut <= #2 EX_MEM_ALUOut;
		LOAD: MEM_WB_LMD <= #2 Mem[EX_MEM_ALUOut];
		STORE: if (TAKEN_BRANCH == 0) //DISABLE WRITE
				Mem[EX_MEM_ALUOut] <= #2 EX_MEM_B;
	endcase
 end
always @(posedge clk1) 	//WB STAGE
	begin 
		if (TAKEN_BRANCH == 0) // DISABLE WRITE IF BRANCH TAKEN
		case (MEM_WB_type)
			RR_ALU: Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUOut; //"RD"
			RM_ALU: Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUOut; //"RT"	
			LOAD: Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_LMD; //"RT"
			HALT: HALTED <= #2 1'b1;
		endcase
	end
endmodule			

module test_mips32; //ADDING THREE NOS 10,20,25 STORED IN PROCESSOR REGISTER AND STORE THE SUM IN R4, R5
 reg clk1, clk2;
 integer k;
 pipe_MIPS32 mips(clk1, clk2);
 initial 
	begin 
		clk1 = 0; clk2 = 0;
		repeat(20)	//Generating two phase lock
		 begin
			#5 clk1 = 1; #5 clk1 = 0;
			#5 clk2 = 1; #5 clk2 = 0;
		 end
	end
 initial 
	begin
		for (k=0; k<31; k = k + 1)
			mips.Reg[k] = k;
		mips.Mem[0] = 32'h2801000a; //ADDI R1,RO,10
		mips.Mem[1] = 32'h28020014; //ADDI R2,RO,20
		mips.Mem[2] = 32'h28030019; //ADDI R3,RO,25
		mips.Mem[3] = 32'h0ce77800; //OR R7,R7,R7--dummy instr.
		mips.Mem[4] = 32'h0ce77800; //OR R7,R7,R7--dummy instr.
		mips.Mem[5] = 32'h00222000; //ADDI R4,R1,R2
		mips.Mem[6] = 32'h0ce77800; //OR R7,R7,R7--dummy instr.
		mips.Mem[7] = 32'h00832800; //ADD R5,R4,R3
		mips.Mem[8] = 32'hfc000000; //HLT
	mips.HALTED = 0;
	mips.PC = 0;
	mips.TAKEN_BRANCH = 0;
	#280
	for (k=0; k<6; k = k + 1)
		$display ("R%1d - %2d", k, mips.Reg[k]);
	end
 initial
	begin 
		$dumpfile("mips.vcd");
		$dumpvars(0,test_mips32);
		#300 $finish;
	end
endmodule

module test2_mips32; //LOAD A WORD STORED IN MEM. LOC. 120, ADD 45 TO IT AND STORE THE RESULT IN MEM. LOC. 121
 reg clk1, clk2;
 integer k;
 pipe_MIPS32 mips(clk1, clk2);
 initial 
	begin 
		clk1 = 0; clk2 = 0;
		repeat(50)	//Generating two phase lock
		 begin
			#5 clk1 = 1; #5 clk1 = 0;
			#5 clk2 = 1; #5 clk2 = 0;
		 end
	end
 initial 
	begin
		for (k=0; k<31; k = k + 1)
			mips.Reg[k] = k;
		mips.Mem[0] = 32'h28010078; //ADDI R1,RO,10
		mips.Mem[1] = 32'h0c631800; //OR R3,R3,R3--dummy instr.
		mips.Mem[2] = 32'h20220000; //LW R2,0(R1)
		mips.Mem[3] = 32'h0c631800; //OR R3,R3,R3--dummy instr.
		mips.Mem[4] = 32'h2842002d; //ADDI R2,R2,45
		mips.Mem[5] = 32'h0c631800; //OR R3,R3,R3--dummy instr.
		mips.Mem[6] = 32'h24220001; //SW R2,1(R1)
		mips.Mem[7] = 32'hfc000000; //HLT
		mips.Mem[120] = 85; 
mips.PC = 0;
	mips.HALTED = 0;
	mips.TAKEN_BRANCH = 0;
	#500 $display ("Mem[120]: %4d\nMem[121]:%4d", mips.Mem[120], mips.Mem[121]);
	end
 initial
	begin 
		$dumpfile("mips.vcd");
		$dumpvars(0,test2_mips32);
		#600 $finish;
	end
endmodule

module test3_mips32; //FACTORIAL OF A NO N STORED AT MEM LOC 200 AND STORE THE RESULT IN MEM. LOC. 198
 reg clk1, clk2;
 integer k;
 pipe_MIPS32 mips(clk1, clk2);
 initial 
	begin 
		clk1 = 0; clk2 = 0;
		repeat(50)	//Generating two phase lock
		 begin
			#5 clk1 = 1; #5 clk1 = 0;
			#5 clk2 = 1; #5 clk2 = 0;
		 end
	end
 initial 
	begin
		for (k=0; k<31; k = k + 1)
			mips.Reg[k] = k;
		mips.Mem[0] = 32'h280a00c8; //ADDI R10,RO,200
		mips.Mem[1] = 32'h28020001; //ADDI R2,R0,1
		mips.Mem[2] = 32'h0e94a000; //OR R20,R20,R20 -- dummy instr.
		mips.Mem[3] = 32'h21430000; //LW R3,0(R10)
		mips.Mem[4] = 32'h0e94a000; //OR R20,R20,R20 -- dummy instr.
		mips.Mem[5] = 32'h14431000; //LOOP:MUL R2,R2,R3
		mips.Mem[6] = 32'h2c630001; //SUBI R3,R3,1
		mips.Mem[7] = 32'h0e94a000; //OR R20,R20,R20 -- dummy instr.
		mips.Mem[8] = 32'h3460fffc; //BNEQZ R3,LOOP(i.e. -4 offset)
		mips.Mem[9] = 32'h2542fffe; //SW R2,-2(R10)
		mips.Mem[10] = 32'hfc000000; //HLT 
		mips.Mem[200] = 7; //FINF FACTORIAL OF 7
	mips.PC = 0;
	mips.HALTED = 0;
	mips.TAKEN_BRANCH = 0;
	#2000 $display ("Mem[200]= %2d, Mem[198]=%6d", mips.Mem[200], mips.Mem[198]);
	end
 initial
	begin 
		$dumpfile("mips.vcd");
		$dumpvars(0,test3_mips32);
		$monitor ("R2:%4d",mips.Reg[2]);
		#3000 $finish;
	end
endmodule


