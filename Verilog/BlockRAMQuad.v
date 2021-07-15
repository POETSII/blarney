// Quad-port block RAM
// ===================

module BlockRAMQuad (
  clock,     // Clock
  reset,     // Reset

  DI_A,      // Data in
  RD_ADDR_A, // Read address
  WR_ADDR_A, // Write address
  WE_A,      // Write enable
  RE_A,      // Read enable
  DO_A,      // Data out

  RD_ADDR_B, // Read address
  WR_ADDR_B, // Write address
  DI_B,      // Data in
  WE_B,      // Write enable
  RE_B,      // Read enable
  DO_B       // Data out
  );

  parameter ADDR_WIDTH = 1;
  parameter DATA_WIDTH = 1;
  parameter INIT_FILE  = "UNUSED";

  input [(DATA_WIDTH-1):0] DI_A, DI_B;
  input [(ADDR_WIDTH-1):0] RD_ADDR_A, RD_ADDR_B, WR_ADDR_A, WR_ADDR_B;
  input clock, reset, WE_A, WE_B, RE_A, RE_B;
  output reg [(DATA_WIDTH-1):0] DO_A;
  output reg [(DATA_WIDTH-1):0] DO_B;
  reg [DATA_WIDTH-1:0] RAM[2**ADDR_WIDTH-1:0];

  generate
    if (INIT_FILE != "UNUSED") begin
      initial $readmemh(INIT_FILE, RAM);
    end else begin
      integer i;
      initial
        for (i = 0; i < 2**ADDR_WIDTH; i=i+1)
          RAM[i] = 0;
    end
  endgenerate

  // Port A
  always @(posedge clock) begin
    if (WE_A)
      RAM[WR_ADDR_A] = DI_A;
  end

  always @(posedge clock) begin
    if (RE_A)
      DO_A <= (WE_A && RD_ADDR_A == WR_ADDR_A) ?
        {DATA_WIDTH{1'hx}} : RAM[RD_ADDR_A];
  end

  // Port B
  always @(posedge clock) begin
    if (WE_B)
      RAM[WR_ADDR_B] = DI_B;
  end

  always @(posedge clock) begin
    if (RE_B)
      DO_B <= (WE_B && RD_ADDR_B == WR_ADDR_B) ?
        {DATA_WIDTH{1'hx}} : RAM[RD_ADDR_B];
  end

endmodule
