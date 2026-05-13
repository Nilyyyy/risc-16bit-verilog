//----------------------------------------------------------
// Basit Test Bench
//----------------------------------------------------------
module top;
  reg clk;
  reg rst;

  // Instantiate the processor
  RISC_Processor uut(
    .clk(clk),
    .rst(rst)
  );

  // Saat sinyali
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns per cycle
  end

  // Bellek içini doldurma veya basit test
  initial begin
    rst = 1;
    #20;
    rst = 0;

    // EDA Playground'da basit bir programı
    // InstructionMemory içerisindeki mem dizisine
    // $readmemh("program.hex") ile de yükleyebilirsiniz.
    // Burada manuel birkaç komut koyalım.
    // UUT içerisinden: uut.instr_mem.mem[address] = 16'h....;

    // Örnek Program:
    // pc = 0: add r1, r0, r0   => opcode=0 (ADD), rs=0, rt=0, rd=1 => 0000 000 000 001 000
    // Binary: [15:12]=0000, [11:9]=000, [8:6]=000, [5:3]=001, [2:0]=000 => 0000_000_000_001_000 (0x008?)
    // Kolaylık için kodu decimal / hex ile yazabiliriz.

    // ADD R1, R0, R0
    uut.instr_mem.mem[0] = 16'b0000_000_000_001_000; // 0x010
    // ADDI R2, R1, #5
    // 7 = OPC_ADDI, rs=1, rt=2, imm=5
    // [15:12]=0111, [11:9]=001, [8:6]=010, [5:0]=000101
    // binary = 0111_001_010_000101 => 0x72(0x05) => 0x72(0x05) = 0x72A5?
    uut.instr_mem.mem[1] = 16'b0111_001_010_000101; // 0x7285

    // ADD R3, R2, R2
    // OPC=0, rs=2, rt=2, rd=3 => 0000_010_010_011_000 (0x08D0?)
    uut.instr_mem.mem[2] = 16'b0000_010_010_011_000;

    // SW R3, 0(R0)  => OPC=1001, rs=0, rt=3, imm=0 => 1001_000_011_000000 => 0x9030
    uut.instr_mem.mem[3] = 16'b1001_000_011_000000;

    // LW R4, 0(R0) => 1000_000_100_000000 => 0x8040
    uut.instr_mem.mem[4] = 16'b1000_000_100_000000;

    // J 10 => OPC=1100, address=0000 001010 => 1100_0000001010 => 0xC00A
    uut.instr_mem.mem[5] = 16'b1100_0000_0010_1010; // jump to PC=0x000A

    // Programın ilerisine NOP koyuyoruz
    uut.instr_mem.mem[10] = 16'b0000_0000_0000_0000; // NOP

    // 50-60 cycle civarı bekleyelim
    #600;

    $finish;
  end

  // İsteğe bağlı dalga kaydı
  initial begin
    $dumpfile("risc_pipeline.vcd");
    $dumpvars(0, top);
  end

endmodule