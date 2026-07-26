cmake_minimum_required(VERSION 3.13)
project(CountMemOps C CXX)   # LLVM's config runs C compile checks (FindFFI etc.)

find_package(LLVM REQUIRED CONFIG)
message(STATUS "Using LLVM ${LLVM_PACKAGE_VERSION} from ${LLVM_DIR}")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# plugins must not link LLVM itself: opt already provides the symbols
add_library(CountMemOps MODULE CountMemOps.cpp)
target_include_directories(CountMemOps SYSTEM PRIVATE ${LLVM_INCLUDE_DIRS})
target_compile_definitions(CountMemOps PRIVATE ${LLVM_DEFINITIONS})
if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(CountMemOps PRIVATE -fno-rtti)
endif()
