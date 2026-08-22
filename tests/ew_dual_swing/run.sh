#!/usr/bin/env bash
# Offline check for Metasit_ElliottWave_DualSwing_EA.mq5
#
# There is no MQL5 compiler on Linux, so this translates the EA to rough C++
# (mql2cpp.py + mql_stub.h) and runs the wave-rule engine against synthetic
# price series. It verifies logic, NOT MetaEditor compilation - always press
# F7 in MetaEditor as well.
set -e
cd "$(dirname "$0")"
EA="../../Metasit_ElliottWave_DualSwing_EA.mq5"

python3 mql2cpp.py "$EA" > ea.cpp
g++ -fsyntax-only -std=c++17 -Wall -Wextra -I. ea.cpp
echo "syntax check: OK"

g++ -std=c++17 -Wno-format-security -I. -o test_ea test_ea.cpp
./test_ea
