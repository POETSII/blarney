import Blarney
import Blarney.Stmt
import Blarney.QuadPortRAM

-- Top-level module
top :: Module ()
top = do
  -- Quad-port RAM
  (ramA, ramB) :: (RAM (Bit 8) (Bit 32),
                   RAM (Bit 8) (Bit 32)) <- makeQuadRAM

  -- Counter
  i :: Reg (Bit 8) <- makeReg 0

  -- Simple test sequence
  runStmt do
    while (i.val .<. 30) do
      action do
        let writeVal = 1 .<<. i.val
        store ramA (i.val) writeVal
        store ramB (100 + i.val) (inv writeVal)
        i <== i.val + 1
    action do
      i <== 0
    while (i.val .<. 30) do
      action do
        load ramA (100 + i.val)
        load ramB (i.val)
      action do
        display "ramA[100+" (i.val) "] = 0x" (formatHex 32 (ramA.out))
        display "ramB[" (i.val) "] = 0x" (formatHex 32 (ramB.out))
        i <== i.val + 1
    action do
      finish

  return ()

-- Main function
main :: IO ()
main = writeVerilogTop top "RAMQuad" "RAMQuad-Verilog/"
