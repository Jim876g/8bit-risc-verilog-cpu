module alu(
    input      [7:0] a,
    input      [7:0] b,
    input      [2:0] alu_op,
    output reg [7:0] y
);
    always @(*) begin
        case (alu_op)
            3'd0:    y = a + b;
            3'd1:    y = a - b;
            3'd2:    y = a & b;
            3'd3:    y = a | b;
            3'd4:    y = a ^ b;
            default: y = 8'd0;
        endcase
    end
endmodule

module regfile(
    input        clk,
    input        rst,
    input        we,
    input  [1:0] waddr,
    input  [7:0] wdata,
    input  [1:0] raddr1,
    input  [1:0] raddr2,
    output [7:0] rdata1,
    output [7:0] rdata2
);
    reg [7:0] regs [0:3];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 4; i = i + 1)
                regs[i] <= 8'd0;
        end else if (we) begin
            regs[waddr] <= wdata;
        end
    end

    assign rdata1 = regs[raddr1];
    assign rdata2 = regs[raddr2];
endmodule

module control(
    input      [3:0] opcode,
    output reg       reg_we,
    output reg [2:0] alu_op,
    output reg       use_imm,
    output reg       mem_to_reg,
    output reg       mem_we,
    output reg       jump,
    output reg       branch,
    output reg       halt
);
    localparam [3:0] OP_NOP  = 4'h0,
                     OP_ADD  = 4'h1,
                     OP_SUB  = 4'h2,
                     OP_AND  = 4'h3,
                     OP_OR   = 4'h4,
                     OP_XOR  = 4'h5,
                     OP_LDI  = 4'h6,
                     OP_LD   = 4'h7,
                     OP_ST   = 4'h8,
                     OP_JMP  = 4'h9,
                     OP_BEQ  = 4'hA,
                     OP_HALT = 4'hF;

    always @(*) begin
        reg_we     = 1'b0;
        alu_op     = 3'd0;
        use_imm    = 1'b0;
        mem_to_reg = 1'b0;
        mem_we     = 1'b0;
        jump       = 1'b0;
        branch     = 1'b0;
        halt       = 1'b0;
        case (opcode)
            OP_ADD:  begin reg_we = 1'b1; alu_op = 3'd0; end
            OP_SUB:  begin reg_we = 1'b1; alu_op = 3'd1; end
            OP_AND:  begin reg_we = 1'b1; alu_op = 3'd2; end
            OP_OR:   begin reg_we = 1'b1; alu_op = 3'd3; end
            OP_XOR:  begin reg_we = 1'b1; alu_op = 3'd4; end
            OP_LDI:  begin reg_we = 1'b1; use_imm = 1'b1; end
            OP_LD:   begin reg_we = 1'b1; mem_to_reg = 1'b1; end
            OP_ST:   mem_we = 1'b1;
            OP_JMP:  jump = 1'b1;
            OP_BEQ:  branch = 1'b1;
            OP_HALT: halt = 1'b1;
            default: ;
        endcase
    end
endmodule

module instr_mem(
    input  [7:0]  addr,
    output [15:0] instr
);
    reg [15:0] mem [0:255];

    assign instr = mem[addr];
endmodule

module data_mem(
    input        clk,
    input        we,
    input  [7:0] addr,
    input  [7:0] wdata,
    output [7:0] rdata
);
    reg [7:0] mem [0:255];

    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
    end

    assign rdata = mem[addr];
endmodule

module cpu(
    input  clk,
    input  rst,
    output halted
);
    reg  [7:0]  pc;
    wire [15:0] instr;
    wire [3:0]  opcode = instr[15:12];
    wire [1:0]  rd     = instr[11:10];
    wire [1:0]  rs     = instr[9:8];
    wire [1:0]  rt     = instr[7:6];
    wire [7:0]  imm8   = instr[7:0];
    wire [7:0]  target = {2'b00, instr[5:0]};

    wire       reg_we;
    wire [2:0] alu_op;
    wire       use_imm;
    wire       mem_to_reg;
    wire       mem_we;
    wire       jump;
    wire       branch;
    wire       halt;

    wire [7:0] rdata1;
    wire [7:0] rdata2;
    wire [7:0] alu_y;
    wire [7:0] dm_rdata;
    wire [7:0] wb_data;
    wire       eq = (rdata1 == rdata2);

    instr_mem u_imem (.addr(pc), .instr(instr));

    control u_ctrl (
        .opcode(opcode), .reg_we(reg_we), .alu_op(alu_op), .use_imm(use_imm),
        .mem_to_reg(mem_to_reg), .mem_we(mem_we), .jump(jump),
        .branch(branch), .halt(halt)
    );

    regfile u_rf (
        .clk(clk), .rst(rst), .we(reg_we),
        .waddr(rd), .wdata(wb_data),
        .raddr1(rs), .raddr2(rt),
        .rdata1(rdata1), .rdata2(rdata2)
    );

    alu u_alu (.a(rdata1), .b(rdata2), .alu_op(alu_op), .y(alu_y));

    data_mem u_dmem (
        .clk(clk), .we(mem_we),
        .addr(rdata1), .wdata(rdata2), .rdata(dm_rdata)
    );

    assign wb_data = use_imm ? imm8 : (mem_to_reg ? dm_rdata : alu_y);
    assign halted  = halt;

    always @(posedge clk) begin
        if (rst)
            pc <= 8'd0;
        else if (!halt) begin
            if (jump || (branch && eq))
                pc <= target;
            else
                pc <= pc + 8'd1;
        end
    end
endmodule

module tb_cpu;
    reg  clk = 1'b0;
    reg  rst;
    wire halted;
    integer i;
    integer cycles;
    integer errors = 0;

    cpu uut(.clk(clk), .rst(rst), .halted(halted));

    always #5 clk = ~clk;

    function [15:0] enc_r(input [3:0] op, input [1:0] rd, input [1:0] rs, input [1:0] rt);
        enc_r = {op, rd, rs, rt, 6'd0};
    endfunction

    function [15:0] enc_ldi(input [1:0] rd, input [7:0] imm);
        enc_ldi = {4'h6, rd, 2'b00, imm};
    endfunction

    function [15:0] enc_beq(input [1:0] rs, input [1:0] rt, input [5:0] target);
        enc_beq = {4'hA, 2'b00, rs, rt, target};
    endfunction

    function [15:0] enc_jmp(input [5:0] target);
        enc_jmp = {4'h9, 6'b000000, target};
    endfunction

    task clear_memories;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                uut.u_imem.mem[i] = 16'h0000;
                uut.u_dmem.mem[i] = 8'h00;
            end
        end
    endtask

    task load_sum_program;
        begin
            uut.u_imem.mem[0]  = enc_ldi(2'd0, 8'd5);
            uut.u_imem.mem[1]  = enc_ldi(2'd1, 8'd0);
            uut.u_imem.mem[2]  = enc_ldi(2'd2, 8'd1);
            uut.u_imem.mem[3]  = enc_ldi(2'd3, 8'd0);
            uut.u_imem.mem[4]  = enc_beq(2'd0, 2'd3, 6'd8);
            uut.u_imem.mem[5]  = enc_r(4'h1, 2'd1, 2'd1, 2'd0);
            uut.u_imem.mem[6]  = enc_r(4'h2, 2'd0, 2'd0, 2'd2);
            uut.u_imem.mem[7]  = enc_jmp(6'd4);
            uut.u_imem.mem[8]  = enc_r(4'h8, 2'd0, 2'd3, 2'd1);
            uut.u_imem.mem[9]  = enc_r(4'h7, 2'd2, 2'd3, 2'd0);
            uut.u_imem.mem[10] = 16'hF000;
        end
    endtask

    task load_logic_program;
        begin
            uut.u_imem.mem[0]  = enc_ldi(2'd0, 8'hF0);
            uut.u_imem.mem[1]  = enc_ldi(2'd1, 8'h3C);
            uut.u_imem.mem[2]  = enc_r(4'h3, 2'd2, 2'd0, 2'd1);
            uut.u_imem.mem[3]  = enc_r(4'h4, 2'd3, 2'd0, 2'd1);
            uut.u_imem.mem[4]  = enc_r(4'h5, 2'd0, 2'd0, 2'd1);
            uut.u_imem.mem[5]  = enc_r(4'h2, 2'd1, 2'd3, 2'd2);
            uut.u_imem.mem[6]  = enc_r(4'h1, 2'd2, 2'd2, 2'd2);
            uut.u_imem.mem[7]  = enc_r(4'h8, 2'd0, 2'd2, 2'd3);
            uut.u_imem.mem[8]  = enc_r(4'h7, 2'd1, 2'd2, 2'd0);
            uut.u_imem.mem[9]  = enc_beq(2'd1, 2'd3, 6'd11);
            uut.u_imem.mem[10] = enc_ldi(2'd0, 8'hAA);
            uut.u_imem.mem[11] = 16'hF000;
        end
    endtask

    task run_until_halt;
        begin
            cycles = 0;
            while (!halted && cycles < 500) begin
                @(posedge clk); #1;
                cycles = cycles + 1;
            end
            if (!halted) begin
                errors = errors + 1;
                $display("FAIL: cpu did not halt within 500 cycles");
            end
        end
    endtask

    task check_reg(input [1:0] r, input [7:0] want);
        begin
            if (uut.u_rf.regs[r] !== want) begin
                errors = errors + 1;
                $display("FAIL: R%0d = %0d, expected %0d", r, uut.u_rf.regs[r], want);
            end
        end
    endtask

    task check_mem(input [7:0] addr, input [7:0] want);
        begin
            if (uut.u_dmem.mem[addr] !== want) begin
                errors = errors + 1;
                $display("FAIL: mem[%0d] = %0d, expected %0d", addr, uut.u_dmem.mem[addr], want);
            end
        end
    endtask

    task check_cycles(input [31:0] want);
        begin
            if (cycles !== want) begin
                errors = errors + 1;
                $display("FAIL: took %0d cycles, expected %0d", cycles, want);
            end
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_cpu);

        rst = 1'b1;
        clear_memories;
        load_sum_program;
        repeat (3) @(posedge clk);
        #1 rst = 1'b0;
        run_until_halt;
        check_reg(2'd0, 8'd0);
        check_reg(2'd1, 8'd15);
        check_reg(2'd2, 8'd15);
        check_reg(2'd3, 8'd0);
        check_mem(8'd0, 8'd15);
        check_cycles(27);

        rst = 1'b1;
        @(posedge clk); #1;
        clear_memories;
        load_logic_program;
        @(posedge clk); #1;
        rst = 1'b0;
        run_until_halt;
        check_reg(2'd0, 8'hCC);
        check_reg(2'd1, 8'hFC);
        check_reg(2'd2, 8'h60);
        check_reg(2'd3, 8'hFC);
        check_mem(8'h60, 8'hFC);
        check_cycles(10);

        if (errors == 0) $display("PASS: tb_cpu (2 programs)");
        else             $display("FAILED: tb_cpu, %0d errors", errors);
        $finish;
    end

    initial begin
        #5000000;
        $display("FAILED: watchdog timeout");
        $finish;
    end
endmodule
