{- Data-flow passes over netlist -}

module Blarney.DataFlow
  ( dataFlow
  , sequentialise
  ) where

import Blarney.Unbit
import qualified Blarney.JList as JL
import qualified Data.IntSet as IS
import qualified Data.Set as S
import qualified Data.Map as M
import Data.Array as A

{-

Data-flow pass
==============

This function introduces data-flow ordering on netlists.  It does so
using a depth-first (post-order) traversal starting from each root.  A
root is: (1) a component with no outputs; or (2) the child of a
register.  A leaf is: (1) any component with no inputs; (2) a
register.  A visited set is used to ensure that the same subtree is
not traversed more than once.  An ancestor set is used to detect
cycles.  Such cycles must be combinatorial cycles since registers are
considered as leaves.

-}

-- Is given net a leaf?
isLeaf :: Net -> Bool
isLeaf net = 
  case netPrim net of
    Register i w   -> True
    RegisterEn i w -> True
    Const i w      -> True
    other          -> False

-- Return nets in data-flow order
dataFlow :: [Net] -> [Net]
dataFlow nets =
    JL.toList 
  . fst
  . dfsList IS.empty IS.empty
  $ roots
  where
    -- Number of nets
    n = length nets

    -- Array mapping net ids to nets
    netArray = array (0, n-1) [(netInstId net, net) | net <- nets]

    -- Lookup net
    lookup i = netArray A.! i

    -- Roots of netlist
    roots = concatMap root nets

    -- Is given net a root?
    root net =
      case netPrim net of
        Register i w   -> map (lookup . fst) (netInputs net)
        RegisterEn i w -> map (lookup . fst) (netInputs net)
        Display args   -> [net]
        Finish         -> [net]
        other          -> []

    -- DFS from a list of root nodes
    dfsList as vs nets =
      case nets of
        []   -> (JL.Zero, vs)
        n:ns -> let (left, vs')  = dfs as vs n
                    (rest, vs'') = dfsList as vs' ns
                in  (left JL.:+: rest, vs'')

    -- DFS from a single root node
    dfs as vs net
      | id `IS.member` as = error "Combinatorial cycle detected"
      | id `IS.member` vs = (JL.Zero, vs)
      | isLeaf net        = (JL.One net, IS.insert id vs)
      | otherwise         = (cs JL.:+: JL.One net, vs')
      where
        id        = netInstId net
        children  = map (lookup . fst) (netInputs net)
        (cs, vs') = dfsList (IS.insert id as) (IS.insert id vs) children

{-

Sequentialisation pass
======================

This pass introduces temporary register variables, where necessary, so
that parallel register updates can be performed sequentially

-}

-- Extract state variables (that are updated on each cycle) from net
getStateVars :: Net -> [(WireId, Width)]
getStateVars net =
  case netPrim net of
    Register i w   -> [((netInstId net, 0), w)]
    RegisterEn i w -> [((netInstId net, 0), w)]
    other          -> []

sequentialise :: [Net] -> [Net]
sequentialise nets = intro (length nets) M.empty nets
  where
    intro id mod [] = []
    intro id mod (net:nets)
      | null stateVars = net : intro id mod nets
      | otherwise      = new ++ [net {netInputs = ins}] ++ intro id' mod' nets
      where
        stateVars       = getStateVars net
        mod'            = M.union (M.fromList stateVars) mod
        (id', new, ins) = replace id (netInputs net)

        replace id [] = (id, [], [])
        replace id (i:is) =
          let (id0, new0, wire)  = rep id i
              (id1, new1, wires) = replace id0 is
          in  (id1, new0 ++ new1, wire:wires)

        rep id i =
          case M.lookup i mod of
            Nothing -> (id, [], i)
            Just w  -> let net = Net { netPrim = Identity w
                                     , netInstId = id
                                     , netInputs = [i]
                                     , netOutputWidths = [w] }
                       in  (id+1, [net], (id, 0))