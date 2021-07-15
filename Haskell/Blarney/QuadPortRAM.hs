{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE NoStarIsType          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE PartialTypeSignatures #-}

{-|
Module      : Blarney.QuadPortRAM
Description : Quad-port block RAMs
Copyright   : (c) Matthew Naylor, 2021
License     : MIT
Maintainer  : mattfn@gmail.com
Stability   : experimental
-}
module Blarney.QuadPortRAM
  ( ramQuad             -- Simple quad-port block RAM primitive
  , makeQuadRAM         -- Quad-port block RAM
  , makeQuadRAMInit     -- Initialised quad-port block RAM
  , makeQuadRAMCore     -- Optionally initialised quad-port block RAM
  ) where

-- Blarney imports
import Blarney
import Blarney.Core.BV
import Blarney.Core.Prim

-- GHC imports
import GHC.TypeNats

-- |Simple quad-port RAM primitive (for internal use only)
-- (Same-port read during write: reads "dont care")
ramQuadPrim :: Int -> Maybe String ->
  (Bit a, Bit a, Bit a, Bit a,
   Bit d, Bit d,
   Bit 1, Bit 1, Bit 1, Bit 1) -> (Bit d, Bit d)
ramQuadPrim dataWidth init
              (ra_a, ra_b, wa_a, wa_b,
               di_a, di_b,
               we_a, we_b, re_a, re_b) =
    (FromBV dataOutA, FromBV dataOutB)
  where
    addrWidth = unsafeWidthOf ra_a

    prim =
      Custom {
        customName = "BlockRAMQuad"
      , customInputs =
          [ ("DI_A", dataWidth)
          , ("RD_ADDR_A", addrWidth)
          , ("WR_ADDR_A", addrWidth)
          , ("WE_A", 1)
          , ("RE_A", 1)

          , ("DI_B", dataWidth)
          , ("RD_ADDR_B", addrWidth)
          , ("WR_ADDR_B", addrWidth)
          , ("WE_B", 1)
          , ("RE_B", 1)
          ]
      , customOutputs =
          [ ("DO_A", dataWidth)
          , ("DO_B", dataWidth)
          ]
      , customParams =
          [ ("ADDR_WIDTH" :-> show addrWidth)
          , ("DATA_WIDTH" :-> show dataWidth)
          ] ++
          [ ("INIT_FILE" :-> filename) | Just filename <- [init] ]
      , customIsClocked = True
      , customNetlist = Nothing
      }

    [dataOutA, dataOutB] =
      makePrim prim [ toBV di_a, toBV ra_a, toBV wa_a
                    , toBV we_a, toBV re_a
                    , toBV di_b, toBV ra_b, toBV wa_b
                    , toBV we_b, toBV re_b ]
                    [ Just "DO_A", Just "DO_B" ]
                    
-- |Uninitialised simple quad-port block RAM.
-- (Same-port read during write: reads "dont care")
ramQuad :: (Bits a, Bits d) =>
     Maybe String
  -> (a, a, a, a, d, d, Bit 1, Bit 1, Bit 1, Bit 1)
  -> (d, d)
ramQuad init (ra_a, ra_b, wa_a, wa_b,
              di_a, di_b,
              we_a, we_b, re_a, re_b) =
    (unpack do_a, unpack do_b)
  where
    dataWidth = sizeOf di_a
    (do_a, do_b) =
      ramQuadPrim dataWidth init
        (pack ra_a, pack ra_b, pack wa_a, pack wa_b,
         pack di_a, pack di_b,
         we_a, we_b, re_a, re_b)

-- |Create uninitialised quad-port RAM.
-- Two read ports, two write ports.
makeQuadRAM :: (Bits a, Bits d) => Module (RAM a d, RAM a d)
makeQuadRAM = makeQuadRAMCore Nothing

-- |Create quad-port RAM with initial contents from hex file.
-- Two read ports, two write ports.
makeQuadRAMInit :: (Bits a, Bits d) => String -> Module (RAM a d, RAM a d)
makeQuadRAMInit init = makeQuadRAMCore (Just init)

-- Simple quad port RAM module.
-- Two read ports, two write ports.
makeQuadRAMCore :: (Bits a, Bits d) =>
     Maybe String
  -> Module (RAM a d, RAM a d)
makeQuadRAMCore init = do
  -- RAM A busses
  rdAddrBusA :: Wire a <- makeWire dontCare
  wrAddrBusA :: Wire a <- makeWire dontCare
  dataBusA   :: Wire d <- makeWire dontCare
  writeEnA   :: Wire (Bit 1) <- makeWire 0
  readEnA    :: Wire (Bit 1) <- makeWire 1

  -- RAM B busses
  rdAddrBusB :: Wire a <- makeWire dontCare
  wrAddrBusB :: Wire a <- makeWire dontCare
  dataBusB   :: Wire d <- makeWire dontCare
  writeEnB   :: Wire (Bit 1) <- makeWire 0
  readEnB    :: Wire (Bit 1) <- makeWire 1

  -- RAM instance
  let (outA, outB) = ramQuad init
        (val rdAddrBusA, val rdAddrBusB, val wrAddrBusA, val wrAddrBusB,
         val dataBusA, val dataBusB,
         val writeEnA, val writeEnB, val readEnA, val readEnB)

  -- Interface A
  let ramA =
        RAM {
          load = (rdAddrBusA <==)
        , store = \a d -> do
                    wrAddrBusA <== a
                    dataBusA <== d
                    writeEnA <== 1
        , out = outA
        , storeActive = val writeEnA
        , preserveOut = readEnA <== 0
        }

  -- Interface B
  let ramB =
        RAM {
          load = (rdAddrBusB <==)
        , store = \a d -> do
                    wrAddrBusB <== a
                    dataBusB <== d
                    writeEnB <== 1
        , out = outB
        , storeActive = val writeEnB
        , preserveOut = readEnB <== 0
        }

  return (ramA, ramB)
