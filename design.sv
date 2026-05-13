`timescale 1ns/1ps

//==========================================================
// 16-bit RISC İşlemci Pipeline Örneği
//==========================================================
//
// Pipeline Aşamaları:
//   IF  -> ID -> EX -> MEM -> WB
//
// Desteklenen Talimatlar (4 bit opcode):
//   R-Tip: ADD, SUB, AND, OR, SLT, SLL, SRL
//   I-Tip: ADDI, LW, SW, BEQ, BNE
//   J-Tip: J, JAL
//   Özel  : JR
//
// Data/Instruction Bellekleri 16-bit kelime tabanlıdır.
//
//==========================================================

//----------------------------------------------------------
// Opcode Tanımları
//----------------------------------------------------------
localparam [3:0] OPC_ADD   = 4'h0;
localparam [3:0] OPC_SUB   = 4'h1;
localparam [3:0] OPC_AND   = 4'h2;
localparam [3:0] OPC_OR    = 4'h3;
localparam [3:0] OPC_SLT   = 4'h4;
localparam [3:0] OPC_SLL   = 4'h5;
localparam [3:0] OPC_SRL   = 4'h6;
localparam [3:0] OPC_ADDI  = 4'h7;
localparam [3:0] OPC_LW    = 4'h8;
localparam [3:0] OPC_SW    = 4'h9;
localparam [3:0] OPC_BEQ   = 4'hA;
localparam [3:0] OPC_BNE   = 4'hB;
localparam [3:0] OPC_J     = 4'hC;
localparam [3:0] OPC_JAL   = 4'hD;
localparam [3:0] OPC_JR    = 4'hE;
// 4'hF şu an kullanılmıyor (NOP gibi düşünebilirsiniz)

//----------------------------------------------------------
// ALU Modülü
//----------------------------------------------------------
module ALU(
    input  wire [3:0]  alu_op,   // opcode
    input  wire [15:0] val_rs,
    input  wire [15:0] val_rt,
    input  wire [2:0]  shamt,    // SLL / SRL için shift amount
    input  wire [5:0]  imm6,     // sign-extend edilecek 6 bit
    output reg  [15:0] alu_out,
    output reg         branch_taken
);

  reg signed [15:0] srs, srt;  // signed yorumlama
  reg signed [15:0] s_imm;
  
  always @* begin
    // Sign-extend 6-bit immediate
    if (imm6[5] == 1'b1) 
      s_imm = {{10{1'b1}}, imm6}; // 6 bit'i işaretli genişlet
    else
      s_imm = {{10{1'b0}}, imm6};

    srs = val_rs;
    srt = val_rt;
    alu_out = 16'h0000;
    branch_taken = 1'b0;
    
    case(alu_op)
      OPC_ADD : alu_out = val_rs + val_rt;
      OPC_SUB : alu_out = val_rs - val_rt;
      OPC_AND : alu_out = val_rs & val_rt;
      OPC_OR  : alu_out = val_rs | val_rt;
      OPC_SLT : alu_out = (srs < srt) ? 16'h0001 : 16'h0000;
      OPC_SLL : alu_out = val_rt << shamt;
      OPC_SRL : alu_out = val_rt >> shamt;
      OPC_ADDI: alu_out = val_rs + s_imm;
      OPC_LW,
      OPC_SW  : alu_out = val_rs + s_imm;  // adrese işaret eder
      OPC_BEQ : begin
                  if (val_rs == val_rt) branch_taken = 1'b1;
                end
      OPC_BNE : begin
                  if (val_rs != val_rt) branch_taken = 1'b1;
                end
      // J, JAL, JR talimatlarında ALU sonucu pek kullanılmaz
      // ama branch_taken veya PC hesaplaması kontrol biriminde veya pipeline logic'te ele alınır
      default: alu_out = 16'h0000;
    endcase
  end
endmodule

//----------------------------------------------------------
// Register Dosyası (8 Register x 16 bit)
//----------------------------------------------------------
module RegisterFile(
    input wire clk,
    input wire we,             // write enable
    input wire [2:0] waddr,
    input wire [15:0] wdata,
    input wire [2:0] raddr1,
    input wire [2:0] raddr2,
    output wire [15:0] rdata1,
    output wire [15:0] rdata2
);

  reg [15:0] regs [0:7];
  integer i;

  // Başlangıçta tüm registerları sıfırla
  initial begin
    for(i=0; i<8; i=i+1) begin
      regs[i] = 16'h0000;
    end
  end

  // Yazma
  always @(posedge clk) begin
    if(we && (waddr != 0)) begin
      regs[waddr] <= wdata;  // R0 = sabit 0 kabul edebiliriz ya da yazılabilir de yapabiliriz
    end
  end

  // Okuma asenkron
  assign rdata1 = regs[raddr1];
  assign rdata2 = regs[raddr2];

endmodule

//----------------------------------------------------------
// Instruction Memory (16 bit x 256 kelime)
// - Burada küçük bir örnek boyut kullandık
//----------------------------------------------------------
module InstructionMemory(
    input  wire [7:0] addr,    // kelime adresi
    output wire [15:0] instr
);

  // Örnek: 256 x 16 bit
  reg [15:0] mem [0:255];

  // Basit bir başlangıç doldurma veya test bench üzerinden
  // $readmemh / $readmemb ile doldurulabilir.
  initial begin
    integer i;
    for(i=0; i<256; i=i+1) begin
      mem[i] = 16'h0000;
    end
  end

  assign instr = mem[addr];

endmodule

//----------------------------------------------------------
// Data Memory (16 bit x 256 kelime)
//----------------------------------------------------------
module DataMemory(
    input  wire clk,
    input  wire mem_write,     // SW
    input  wire mem_read,      // LW
    input  wire [15:0] address,
    input  wire [15:0] write_data,
    output reg  [15:0] read_data
);

  reg [15:0] mem [0:255];
  integer i;

  initial begin
    for(i=0; i<256; i=i+1) begin
      mem[i] = 16'h0000;
    end
    read_data = 16'h0000;
  end

  // Bellek yazma
  always @(posedge clk) begin
    if (mem_write) begin
      // Adresin alt 8 biti index olarak kullanılır
      // (Büyük tasarımlarda hizalama kontrolü de gerekir)
      mem[address[7:0]] <= write_data;
    end
  end

  // Bellek okuma
  always @* begin
    if (mem_read) begin
      read_data = mem[address[7:0]];
    end else begin
      read_data = 16'h0000;
    end
  end

endmodule

//----------------------------------------------------------
// Kontrol Birimi (sadelestirilmis)
// - ID aşamasında opcode'a göre sinyaller üretilir
//----------------------------------------------------------
module ControlUnit(
    input wire [3:0] opcode,
    output reg reg_write,
    output reg mem_read,
    output reg mem_write,
    output reg mem_to_reg,
    output reg alu_src_imm,
    output reg reg_dst_rd,
    output reg link_jal,
    output reg jump_or_branch
);
  always @* begin
    // Varsayılanlar
    reg_write   = 1'b0;
    mem_read    = 1'b0;
    mem_write   = 1'b0;
    mem_to_reg  = 1'b0;
    alu_src_imm = 1'b0;
    reg_dst_rd  = 1'b0;
    link_jal    = 1'b0;
    jump_or_branch = 1'b0;

    case(opcode)
      OPC_ADD, OPC_SUB, OPC_AND, OPC_OR, OPC_SLT, OPC_SLL, OPC_SRL:
      begin
        reg_write   = 1'b1; // R-type
        reg_dst_rd  = 1'b1; // hepsi rd'ye yazar
      end
      OPC_ADDI: begin
        reg_write   = 1'b1; // RT'ye yaz
        alu_src_imm = 1'b1;
      end
      OPC_LW: begin
        reg_write   = 1'b1;
        alu_src_imm = 1'b1;
        mem_read    = 1'b1;
        mem_to_reg  = 1'b1; // Bellekten gelen veri register'a
      end
      OPC_SW: begin
        mem_write   = 1'b1;
        alu_src_imm = 1'b1;
      end
      OPC_BEQ, OPC_BNE: begin
        jump_or_branch = 1'b1; // Branch
      end
      OPC_J, OPC_JAL, OPC_JR: begin
        jump_or_branch = 1'b1; // Jump
        if (opcode == OPC_JAL) begin
          link_jal = 1'b1; // R7'ye link
        end
      end
      default: ; // NOP veya desteklenmeyen
    endcase
  end
endmodule

//----------------------------------------------------------
// Pipeline Register Yapıları
//
// IF/ID, ID/EX, EX/MEM, MEM/WB
//----------------------------------------------------------
module PipelineRegisters #(parameter WIDTH = 16) 
(
    input  wire clk,
    input  wire rst,
    input  wire stall,
    input  wire flush,
    //------------------------------------------------------
    // IF -> ID
    //------------------------------------------------------
    input  wire [15:0] if_instr_in,
    input  wire [15:0] if_pc_in,
    output reg  [15:0] id_instr_out,
    output reg  [15:0] id_pc_out,
    //------------------------------------------------------
    // ID -> EX (Control signals + register values + imm vs.)
    //------------------------------------------------------
    input  wire [3:0]  id_opcode_in,
    input  wire [15:0] id_val_rs_in,
    input  wire [15:0] id_val_rt_in,
    input  wire [2:0]  id_rs_in,
    input  wire [2:0]  id_rt_in,
    input  wire [2:0]  id_rd_in,
    input  wire [2:0]  id_shamt_in,
    input  wire [5:0]  id_imm_in,
    input  wire [11:0] id_address_in,
    // control
    input  wire id_reg_write_in,
    input  wire id_mem_read_in,
    input  wire id_mem_write_in,
    input  wire id_mem_to_reg_in,
    input  wire id_alu_src_imm_in,
    input  wire id_reg_dst_rd_in,
    input  wire id_link_jal_in,
    input  wire id_jump_or_branch_in,

    output reg  [3:0]  ex_opcode_out,
    output reg  [15:0] ex_val_rs_out,
    output reg  [15:0] ex_val_rt_out,
    output reg  [2:0]  ex_rs_out,
    output reg  [2:0]  ex_rt_out,
    output reg  [2:0]  ex_rd_out,
    output reg  [2:0]  ex_shamt_out,
    output reg  [5:0]  ex_imm_out,
    output reg  [11:0] ex_address_out,
    output reg         ex_reg_write_out,
    output reg         ex_mem_read_out,
    output reg         ex_mem_write_out,
    output reg         ex_mem_to_reg_out,
    output reg         ex_alu_src_imm_out,
    output reg         ex_reg_dst_rd_out,
    output reg         ex_link_jal_out,
    output reg         ex_jump_or_branch_out,
    output reg  [15:0] ex_pc_out,
    //------------------------------------------------------
    // EX -> MEM
    //------------------------------------------------------
    input  wire [15:0] ex_alu_result_in,
    input  wire        ex_branch_taken_in,
    // control
    input  wire        ex_reg_write_in,
    input  wire        ex_mem_read_in,
    input  wire        ex_mem_write_in,
    input  wire        ex_mem_to_reg_in,
    input  wire        ex_link_jal_in,
    output reg  [15:0] mem_alu_result_out,
    output reg         mem_branch_taken_out,
    output reg         mem_reg_write_out,
    output reg         mem_mem_read_out,
    output reg         mem_mem_write_out,
    output reg         mem_mem_to_reg_out,
    output reg         mem_link_jal_out,
    output reg  [2:0]  mem_rd_out, // hangi registera yazacağız?
    output reg  [2:0]  mem_rt_out,
    output reg  [15:0] mem_val_rt_out, // SW için rt değeri lazım
    output reg  [15:0] mem_pc_out,
    output reg  [3:0]  mem_opcode_out,
    //------------------------------------------------------
    // MEM -> WB
    //------------------------------------------------------
    input  wire [15:0] mem_read_data_in,
    // control
    input  wire        mem_reg_write_in,
    input  wire        mem_mem_to_reg_in,
    input  wire        mem_link_jal_in,
    output reg  [15:0] wb_alu_result_out,
    output reg  [15:0] wb_read_data_out,
    output reg         wb_reg_write_out,
    output reg         wb_mem_to_reg_out,
    output reg         wb_link_jal_out,
    output reg  [2:0]  wb_rd_out,
    output reg  [2:0]  wb_rt_out,
    output reg  [3:0]  wb_opcode_out,
    output reg  [15:0] wb_pc_out
);

  //--------------------------------------------------------
  // IF/ID Kayıtları
  //--------------------------------------------------------
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      id_instr_out <= 16'h0000;
      id_pc_out    <= 16'h0000;
    end else if(flush) begin
      // Flush sırasında ID aşamasına girenler NOP olarak ayarlanır
      id_instr_out <= 16'h0000;
      id_pc_out    <= 16'h0000;
    end else if(!stall) begin
      // Normal durumda güncelle
      id_instr_out <= if_instr_in;
      id_pc_out    <= if_pc_in;
    end else begin
      // Stall durumunda IF/ID registerları korunur
      id_instr_out <= id_instr_out;
      id_pc_out    <= id_pc_out;
    end
  end

  //--------------------------------------------------------
  // ID/EX Kayıtları
  //--------------------------------------------------------
  always @(posedge clk or posedge rst) begin
    if(rst || flush) begin
      ex_opcode_out       <= 4'hF; // NOP
      ex_val_rs_out       <= 16'h0000;
      ex_val_rt_out       <= 16'h0000;
      ex_rs_out           <= 3'h0;
      ex_rt_out           <= 3'h0;
      ex_rd_out           <= 3'h0;
      ex_shamt_out        <= 3'h0;
      ex_imm_out          <= 6'h00;
      ex_address_out      <= 12'h000;
      ex_reg_write_out    <= 1'b0;
      ex_mem_read_out     <= 1'b0;
      ex_mem_write_out    <= 1'b0;
      ex_mem_to_reg_out   <= 1'b0;
      ex_alu_src_imm_out  <= 1'b0;
      ex_reg_dst_rd_out   <= 1'b0;
      ex_link_jal_out     <= 1'b0;
      ex_jump_or_branch_out <= 1'b0;
      ex_pc_out           <= 16'h0000;
    end else if(!stall) begin
      ex_opcode_out       <= id_opcode_in;
      ex_val_rs_out       <= id_val_rs_in;
      ex_val_rt_out       <= id_val_rt_in;
      ex_rs_out           <= id_rs_in;
      ex_rt_out           <= id_rt_in;
      ex_rd_out           <= id_rd_in;
      ex_shamt_out        <= id_shamt_in;
      ex_imm_out          <= id_imm_in;
      ex_address_out      <= id_address_in;
      ex_reg_write_out    <= id_reg_write_in;
      ex_mem_read_out     <= id_mem_read_in;
      ex_mem_write_out    <= id_mem_write_in;
      ex_mem_to_reg_out   <= id_mem_to_reg_in;
      ex_alu_src_imm_out  <= id_alu_src_imm_in;
      ex_reg_dst_rd_out   <= id_reg_dst_rd_in;
      ex_link_jal_out     <= id_link_jal_in;
      ex_jump_or_branch_out <= id_jump_or_branch_in;
      ex_pc_out           <= id_pc_out;
    end else begin
      // Stall
      ex_opcode_out <= ex_opcode_out;
    end
  end

  //--------------------------------------------------------
  // EX/MEM Kayıtları
  //--------------------------------------------------------
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      mem_alu_result_out  <= 16'h0000;
      mem_branch_taken_out <= 1'b0;
      mem_reg_write_out   <= 1'b0;
      mem_mem_read_out    <= 1'b0;
      mem_mem_write_out   <= 1'b0;
      mem_mem_to_reg_out  <= 1'b0;
      mem_link_jal_out    <= 1'b0;
      mem_rd_out          <= 3'h0;
      mem_rt_out          <= 3'h0;
      mem_val_rt_out      <= 16'h0000;
      mem_pc_out          <= 16'h0000;
      mem_opcode_out      <= 4'hF; // NOP
    end else begin
      mem_alu_result_out  <= ex_alu_result_in;
      mem_branch_taken_out <= ex_branch_taken_in;
      mem_reg_write_out   <= ex_reg_write_in;
      mem_mem_read_out    <= ex_mem_read_in;
      mem_mem_write_out   <= ex_mem_write_in;
      mem_mem_to_reg_out  <= ex_mem_to_reg_in;
      mem_link_jal_out    <= ex_link_jal_in;
      mem_rd_out          <= ex_reg_dst_rd_out ? ex_rd_out : ex_rt_out;
      mem_rt_out          <= ex_rt_out; // SW için
      mem_val_rt_out      <= ex_val_rt_out; 
      mem_pc_out          <= ex_pc_out;
      mem_opcode_out      <= ex_opcode_out;
    end
  end

  //--------------------------------------------------------
  // MEM/WB Kayıtları
  //--------------------------------------------------------
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      wb_alu_result_out <= 16'h0000;
      wb_read_data_out  <= 16'h0000;
      wb_reg_write_out  <= 1'b0;
      wb_mem_to_reg_out <= 1'b0;
      wb_link_jal_out   <= 1'b0;
      wb_rd_out         <= 3'h0;
      wb_rt_out         <= 3'h0;
      wb_opcode_out     <= 4'hF;
      wb_pc_out         <= 16'h0000;
    end else begin
      wb_alu_result_out <= mem_alu_result_out;
      wb_read_data_out  <= mem_read_data_in;
      wb_reg_write_out  <= mem_reg_write_in;
      wb_mem_to_reg_out <= mem_mem_to_reg_in;
      wb_link_jal_out   <= mem_link_jal_in;
      wb_rd_out         <= mem_rd_out;
      wb_rt_out         <= mem_rt_out;
      wb_opcode_out     <= mem_opcode_out;
      wb_pc_out         <= mem_pc_out;
    end
  end

endmodule

//----------------------------------------------------------
// Hazard Detection Unit (Basit)
// - Load-use stall
// - Branch/Jump flush
//----------------------------------------------------------
module HazardUnit(
    input wire [3:0]  id_ex_opcode,
    input wire [2:0]  id_ex_rt,
    input wire        id_ex_mem_read,
    input wire [2:0]  if_id_rs,
    input wire [2:0]  if_id_rt,
    output reg        stall
);
  always @* begin
    // Default
    stall = 1'b0;
    // Load-use stall:
    // Eğer ID/EX aşamasında LW varsa (id_ex_mem_read=1) ve 
    // bu LW talimatının rt register'ı, IF/ID aşamasındaki
    // talimatın rs veya rt register'ına eşitse, stall gerek.
    if (id_ex_mem_read == 1'b1) begin
      if ((id_ex_rt == if_id_rs) || (id_ex_rt == if_id_rt)) begin
        stall = 1'b1;
      end
    end
  end
endmodule

//----------------------------------------------------------
// Top Seviyede RISC Pipeline
//----------------------------------------------------------
module RISC_Processor(
    input wire clk,
    input wire rst
);

  // Program Sayacı (PC)
  reg [15:0] pc;
  wire [15:0] pc_next;
  wire [15:0] instr;

  // IF/ID
  wire [15:0] if_instr;
  wire [15:0] if_pc;
  wire [15:0] id_instr;
  wire [15:0] id_pc;

  // ID -> Kontrol Sinyalleri
  wire [3:0]  id_opcode;
  wire        c_reg_write, c_mem_read, c_mem_write, c_mem_to_reg;
  wire        c_alu_src_imm, c_reg_dst_rd, c_link_jal, c_jump_or_branch;

  // ID Register File okumaları
  wire [2:0] id_rs = id_instr[11:9];
  wire [2:0] id_rt = id_instr[8:6];
  wire [2:0] id_rd = id_instr[5:3];
  wire [2:0] id_shamt = id_instr[2:0];
  wire [5:0] id_imm = id_instr[5:0];
  wire [11:0] id_address = id_instr[11:0];

  wire [15:0] val_rs, val_rt;

  // ID/EX
  wire [3:0]  ex_opcode;
  wire [15:0] ex_val_rs, ex_val_rt;
  wire [2:0]  ex_rs, ex_rt, ex_rd, ex_shamt;
  wire [5:0]  ex_imm;
  wire [11:0] ex_address;
  wire        ex_reg_write, ex_mem_read, ex_mem_write, ex_mem_to_reg;
  wire        ex_alu_src_imm, ex_reg_dst_rd, ex_link_jal, ex_jump_or_branch;
  wire [15:0] ex_pc;

  // EX çıkış
  wire [15:0] alu_out;
  wire        branch_taken;
  // Seçilen ALU operand (val_rt veya imm)
  wire [15:0] ex_op2 = (ex_alu_src_imm) ? {{10{ex_imm[5]}}, ex_imm} : ex_val_rt;

  // EX/MEM
  wire [15:0] mem_alu_result;
  wire        mem_branch_taken;
  wire        mem_reg_write, mem_mem_read, mem_mem_write, mem_mem_to_reg;
  wire        mem_link_jal;
  wire [2:0]  mem_rd, mem_rt;
  wire [15:0] mem_val_rt;
  wire [15:0] mem_pc;
  wire [3:0]  mem_opcode;

  // MEM -> read_data
  wire [15:0] mem_read_data;

  // MEM/WB
  wire [15:0] wb_alu_result;
  wire [15:0] wb_read_data;
  wire        wb_reg_write, wb_mem_to_reg, wb_link_jal;
  wire [2:0]  wb_rd, wb_rt;
  wire [3:0]  wb_opcode;
  wire [15:0] wb_pc;

  // Hazard / Stall / Flush
  wire hazard_stall;
  reg flush;

  //--------------------------------------------------------
  // Instruction Memory
  //--------------------------------------------------------
  InstructionMemory instr_mem(
    .addr(pc[7:0]),
    .instr(if_instr)
  );

  assign if_pc = pc;

  //--------------------------------------------------------
  // Kontrol Birimi
  //--------------------------------------------------------
  assign id_opcode = id_instr[15:12];
  ControlUnit ctrl_unit(
    .opcode(id_opcode),
    .reg_write(c_reg_write),
    .mem_read(c_mem_read),
    .mem_write(c_mem_write),
    .mem_to_reg(c_mem_to_reg),
    .alu_src_imm(c_alu_src_imm),
    .reg_dst_rd(c_reg_dst_rd),
    .link_jal(c_link_jal),
    .jump_or_branch(c_jump_or_branch)
  );

  //--------------------------------------------------------
  // Register Dosyası
  //--------------------------------------------------------
  RegisterFile regfile(
    .clk(clk),
    .we(wb_reg_write),
    .waddr( wb_mem_to_reg ? wb_rt : wb_rd ), // Belirli talimatlarda rt'yi de yazabilir.
    // Yukarıdaki atama duruma göre tasarlanabilir (R-type => rd, I-type => rt)
    // Bu örnek tasarımda pipeline registerlarda düzeltme yapıldığından,
    // MEM aşamasında "mem_rd_out" vs. seçiliyor. Aşağıdaki basit:
    .wdata( (wb_link_jal) ? (wb_pc + 16'd1) :
            (wb_mem_to_reg ? wb_read_data : wb_alu_result) ),
    .raddr1(id_rs),
    .raddr2(id_rt),
    .rdata1(val_rs),
    .rdata2(val_rt)
  );

  //--------------------------------------------------------
  // ALU
  //--------------------------------------------------------
  ALU alu(
    .alu_op(ex_opcode),
    .val_rs(ex_val_rs),
    .val_rt(ex_op2),
    .shamt(ex_shamt),
    .imm6(ex_imm),
    .alu_out(alu_out),
    .branch_taken(branch_taken)
  );

  //--------------------------------------------------------
  // Data Memory
  //--------------------------------------------------------
  DataMemory data_mem(
    .clk(clk),
    .mem_write(mem_mem_write),
    .mem_read(mem_mem_read),
    .address(mem_alu_result),
    .write_data(mem_val_rt),
    .read_data(mem_read_data)
  );

  //--------------------------------------------------------
  // Pipeline Registers
  //--------------------------------------------------------
  PipelineRegisters pipe_regs(
    .clk(clk),
    .rst(rst),
    .stall(hazard_stall),
    .flush(flush),
    // IF -> ID
    .if_instr_in(if_instr),
    .if_pc_in(if_pc),
    .id_instr_out(id_instr),
    .id_pc_out(id_pc),
    // ID -> EX
    .id_opcode_in(id_opcode),
    .id_val_rs_in(val_rs),
    .id_val_rt_in(val_rt),
    .id_rs_in(id_rs),
    .id_rt_in(id_rt),
    .id_rd_in(id_rd),
    .id_shamt_in(id_shamt),
    .id_imm_in(id_imm),
    .id_address_in(id_address),
    .id_reg_write_in(c_reg_write),
    .id_mem_read_in(c_mem_read),
    .id_mem_write_in(c_mem_write),
    .id_mem_to_reg_in(c_mem_to_reg),
    .id_alu_src_imm_in(c_alu_src_imm),
    .id_reg_dst_rd_in(c_reg_dst_rd),
    .id_link_jal_in(c_link_jal),
    .id_jump_or_branch_in(c_jump_or_branch),

    .ex_opcode_out(ex_opcode),
    .ex_val_rs_out(ex_val_rs),
    .ex_val_rt_out(ex_val_rt),
    .ex_rs_out(ex_rs),
    .ex_rt_out(ex_rt),
    .ex_rd_out(ex_rd),
    .ex_shamt_out(ex_shamt),
    .ex_imm_out(ex_imm),
    .ex_address_out(ex_address),
    .ex_reg_write_out(ex_reg_write),
    .ex_mem_read_out(ex_mem_read),
    .ex_mem_write_out(ex_mem_write),
    .ex_mem_to_reg_out(ex_mem_to_reg),
    .ex_alu_src_imm_out(ex_alu_src_imm),
    .ex_reg_dst_rd_out(ex_reg_dst_rd),
    .ex_link_jal_out(ex_link_jal),
    .ex_jump_or_branch_out(ex_jump_or_branch),
    .ex_pc_out(ex_pc),
    // EX -> MEM
    .ex_alu_result_in(alu_out),
    .ex_branch_taken_in(branch_taken),
    .ex_reg_write_in(ex_reg_write),
    .ex_mem_read_in(ex_mem_read),
    .ex_mem_write_in(ex_mem_write),
    .ex_mem_to_reg_in(ex_mem_to_reg),
    .ex_link_jal_in(ex_link_jal),
    .mem_alu_result_out(mem_alu_result),
    .mem_branch_taken_out(mem_branch_taken),
    .mem_reg_write_out(mem_reg_write),
    .mem_mem_read_out(mem_mem_read),
    .mem_mem_write_out(mem_mem_write),
    .mem_mem_to_reg_out(mem_mem_to_reg),
    .mem_link_jal_out(mem_link_jal),
    .mem_rd_out(mem_rd),
    .mem_rt_out(mem_rt),
    .mem_val_rt_out(mem_val_rt),
    .mem_pc_out(mem_pc),
    .mem_opcode_out(mem_opcode),
    // MEM -> WB
    .mem_read_data_in(mem_read_data),
    .mem_reg_write_in(mem_reg_write),
    .mem_mem_to_reg_in(mem_mem_to_reg),
    .mem_link_jal_in(mem_link_jal),
    .wb_alu_result_out(wb_alu_result),
    .wb_read_data_out(wb_read_data),
    .wb_reg_write_out(wb_reg_write),
    .wb_mem_to_reg_out(wb_mem_to_reg),
    .wb_link_jal_out(wb_link_jal),
    .wb_rd_out(wb_rd),
    .wb_rt_out(wb_rt),
    .wb_opcode_out(wb_opcode),
    .wb_pc_out(wb_pc)
  );

  //--------------------------------------------------------
  // Hazard Unit
  //--------------------------------------------------------
  HazardUnit hazard(
    .id_ex_opcode(ex_opcode),
    .id_ex_rt(ex_rt),
    .id_ex_mem_read(ex_mem_read),
    .if_id_rs(id_rs),
    .if_id_rt(id_rt),
    .stall(hazard_stall)
  );

  //--------------------------------------------------------
  // PC Hesaplamaları
  //--------------------------------------------------------
  always @* begin
    flush = 1'b0;
    // jump_or_branch dediyse ve branch_taken ya da jump ise
    // pipeline flush / pc değiştir.
    if (ex_jump_or_branch) begin
      // Jump ? Branch ? 
      // Jump: ex_opcode = J, JAL, JR
      // Branch: ex_opcode = BEQ, BNE (branch_taken)
      if (ex_opcode == OPC_J) begin
        flush = 1'b1;
      end else if (ex_opcode == OPC_JAL) begin
        flush = 1'b1;
      end else if (ex_opcode == OPC_JR) begin
        flush = 1'b1;
      end else if ((ex_opcode == OPC_BEQ || ex_opcode == OPC_BNE) && branch_taken) begin
        flush = 1'b1;
      end
    end
  end

  // Sıradaki PC
  wire [15:0] jump_target = (ex_opcode == OPC_JR) ? ex_val_rs : {4'h0, ex_address}; 
  wire [15:0] branch_target = ex_pc + {{10{ex_imm[5]}}, ex_imm};
  
  assign pc_next =
    (ex_opcode == OPC_J)   ? jump_target :
    (ex_opcode == OPC_JAL) ? jump_target :
    (ex_opcode == OPC_JR)  ? jump_target :
    ((ex_opcode == OPC_BEQ || ex_opcode == OPC_BNE) && branch_taken) ? branch_target :
    pc + 16'd1;

  // PC Register
  always @(posedge clk or posedge rst) begin
    if(rst) begin
      pc <= 16'h0000;
    end else begin
      if(hazard_stall)
        pc <= pc;  // stall durumunda pc sabit kalsın
      else if(flush)
        pc <= pc_next; // flush durumunda branch/jump
      else
        pc <= pc_next; // normal
    end
  end

endmodule

