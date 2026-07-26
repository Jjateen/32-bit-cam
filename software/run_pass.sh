#!/usr/bin/env bash
# Build the pass, compile test.c to LLVM IR, and run the pass over it.
# Standalone: does not need the Makefile.
#   ./run_pass.sh [source.c]
set -euo pipefail
cd "$(dirname "$0")"

SRC=${1:-test.c}
LL="${SRC%.c}.ll"
PLUGIN=build/libCountMemOps.so

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build build >/dev/null

# -disable-O0-optnone: without it clang marks functions optnone at -O0, which
# blocks analysis. The IR is unoptimised either way.
clang -O0 -Xclang -disable-O0-optnone -S -emit-llvm "$SRC" -o "$LL"

opt -load-pass-plugin="$PLUGIN" -passes=count-mem-ops -disable-output "$LL"
