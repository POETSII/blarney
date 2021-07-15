#! /usr/bin/env bash

# script's static configuration
################################################################################

BLARNEY_DEFAULT_EXAMPLES=(
  Background
  BasicRTL
  Bit0
  BitPat
  BitScan
  CPU
  Derive
  FIFO
  Factorial
  Interface
  Lookup
  MasterSlave
  MeanFilter
  NameBits
  NoC
  Option
  Queue
  RAM
  RAMBE
  RAMQuad
  Sorter
  SourceSink
  Stack
  Counter
  Vectors
)
BLARNEY_EXAMPLES="${BLARNEY_EXAMPLES[@]:-${BLARNEY_DEFAULT_EXAMPLES[@]}}"

# exclude those from being tested, for whatever reason (mainly expected failure)
VERILOG_EXCLUDE=()
SIMULATION_EXCLUDE=(
  Bit0
  Spec
  Interface
  MasterSlave
  RAMQuad
)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# control variables
################################################################################

doBackendDefault=yup
doBackendSimulation=
doBackendVerilog=
doPluginNamer=
doPassNameProp=
doPassSimplifier=
verbose=0

# preliminary checks and script arguments processing
################################################################################

if [ -z "$BLARNEY_ROOT" ]; then
  echo Please set the BLARNEY_ROOT environment variable
fi
BLARNEY_TESTING_ROOT="${BLARNEY_TESTING_ROOT:-$BLARNEY_ROOT}"

while :
do
  case $1 in
    ############################################################################
    -h|--help)
      echo "Runs the blarney examples as a regression test suite"
      echo "--backend-simulation"
      echo "    runs the in haskell simulation backend"
      echo "--backend-verilog"
      echo "    runs the verilog backend and a verilator simulation"
      echo "--plugin-namer"
      echo "    runs blc with the namer plugin enabled"
      echo "--pass-name-propagation"
      echo "    runs the circuit generator with the name propagation netlist pass enabled"
      echo "--pass-simplifier"
      echo "    runs the circuit generator with the netlist optimisation passes enabled"
      echo "--backend-all"
      echo "    same as --backend-simulation and --backend-verilog"
      echo "--preserve-names"
      echo "    same as --plugin-namer and --pass-name-propagation"
      exit
      ;;
    --backend-simulation)
      doBackendDefault=
      doBackendSimulation=yup
      ;;
    --backend-verilog)
      doBackendDefault=
      doBackendVerilog=yup
      ;;
    --plugin-namer)
      doPluginNamer=yup
      ;;
    --pass-name-propagation)
      doPassNameProp=yup
      ;;
    --pass-simplifier)
      doPassSimplifier=yup
      ;;
    --backend-all)
      doBackendDefault=
      doBackendSimulation=yup
      doBackendVerilog=yup
      ;;
    --preserve-names)
      doPluginNamer=yup
      doPassNameProp=yup
      ;;
    -v|--verbose)
      verbose=$((verbose + 1))
      ;;
    ############################################################################
    -?*)
      printf 'Ignoring unknown flag: %s\n' "$1" >&2
      ;;
    --)
      shift
      break
      ;;
    *)
      break
  esac
  shift
done
# assign a default backend if necessary
if [ $doBackendDefault ]; then doBackendVerilog=yup; fi

# Run regression tests
################################################################################

# prepare flags
BLC_FLAGS=()
if [ $doPluginNamer ]; then BLC_FLAGS+=("--enable-namer-plugin"); fi
GEN_FLAGS=()
if [ $doPassNameProp ]; then GEN_FLAGS+=("--enable-name-prop"); fi
if [ $doPassSimplifier ]; then GEN_FLAGS+=("--enable-simplifier"); fi

# reporting variables
nbTests=0
failedTests=()

# start with building the blarney library itself
pushd $BLARNEY_ROOT > /dev/null
echo -n "Blarney build (blc): "
make clean > /dev/null
tmpLog=$(mktemp -t blarney-initial-blc-build-XXXX.log)
make blc-build &> $tmpLog
if [ $? != 0 ]; then
  echo -e "${RED}KO${NC}"
  echo "content of $tmpLog:"
  cat $tmpLog
  exit -1
else echo -e "${GREEN}OK${NC}"
fi
popd > /dev/null

# go through each examples
for E in ${BLARNEY_EXAMPLES[@]}; do
  # work in a temporary directory
  ###############################
  exDir=$BLARNEY_TESTING_ROOT/Examples/$E
  tmpDir=$(mktemp -d -t blarney-test-$E-XXXX)
  cp -r $exDir/* $tmpDir/.
  pushd $tmpDir > /dev/null
  # run each test in the blarney example
  ######################################
  outputs=$(ls *.out)
  for O in $outputs; do
    testName=$(basename $O .out)
    # build the blarney example
    ###########################
    make -s BLC_FLAGS=$BLC_FLAGS $testName &> build.log
    if [ $? != 0 ]; then
      echo -e "${RED}Failed to build $testName${NC}"
      echo "content of $tmpDir/build.log:"
      cat $tmpDir/build.log
      exit -1
    fi
    # test verilog
    ##############
    if [ $doBackendVerilog ] && [[ ! " ${VERILOG_EXCLUDE[@]} " =~ " ${testName} " ]]; then
      printf "%-12s %12s" $testName "verilog"
      ./$testName $GEN_FLAGS --verilog
      make -s -C $testName-Verilog &> $testName-test-verilog.log
      # Using 'sed \$d' to print all but the last line (works on Linux and OSX)
      # ('head -n -1' isn't available on OSX)
      $testName-Verilog/$testName | sed \$d &> $testName-test-verilog.out
      cmp -s $testName.out $testName-test-verilog.out
      if [ $? == 0 ]; then
        printf "${GREEN}%10s${NC}\n" "Passed"
      else
        printf "${RED}%10s${NC}\n" "Failed"
        failedTests+=("$testName-verilog ($tmpDir/$testName-test-verilog.{log, out})")
      fi
      nbTests=$((nbTests+1))
    fi
    # test simulation
    #################
    if [ $doBackendSimulation ] && [[ ! " ${SIMULATION_EXCLUDE[@]} " =~ " ${testName} " ]]; then
      printf "%-12s %12s" $testName "simulation"
      ./$testName $GEN_FLAGS --simulate &> $testName-test-sim.out
      cmp -s $testName.out $testName-test-sim.out
      if [ $? == 0 ]; then
        printf "${GREEN}%10s${NC}\n" "Passed"
      else
        printf "${RED}%10s${NC}\n" "Failed"
        failedTests+=("$testName-sim ($tmpDir/$testName-test-sim.out)")
      fi
      nbTests=$((nbTests+1))
    fi
  done
  popd > /dev/null
done

# reporting
nbFailedTests=${#failedTests[*]}
nbPassedTests=$((nbTests-nbFailedTests))
echo -e "passed ${GREEN}$nbPassedTests${NC} tests (ran $nbTests)"
if [ $nbFailedTests -ne 0 ]; then
  echo -e "Failed ${RED}$nbFailedTests${NC} tests:"
  for i in ${!failedTests[*]}; do echo -e "  - ${failedTests[$i]}"; done
  exit -1
fi
