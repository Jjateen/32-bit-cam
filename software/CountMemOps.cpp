// Counts load and store instructions in every function of a module.
//
// Built as an out-of-tree plugin for the new pass manager, so it is loaded with
// opt -load-pass-plugin=... -passes=count-mem-ops. The pass only reads the IR;
// it reports counts and leaves the module unchanged.

#include "llvm/IR/PassManager.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Passes/PassBuilder.h"
#include "llvm/Passes/PassPlugin.h"
#include "llvm/Support/Format.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

namespace {

struct CountMemOps : PassInfoMixin<CountMemOps> {
    PreservedAnalyses run(Module &M, ModuleAnalysisManager &) {
        unsigned totalLoads = 0, totalStores = 0;

        outs() << "module: " << M.getName() << "\n";
        outs() << "  loads  stores  function\n";

        for (Function &F : M) {
            if (F.isDeclaration())     // no body, nothing to count
                continue;

            unsigned loads = 0, stores = 0;
            for (BasicBlock &BB : F)
                for (Instruction &I : BB) {
                    if (isa<LoadInst>(&I))
                        ++loads;
                    else if (isa<StoreInst>(&I))
                        ++stores;
                }

            outs() << format("  %5u  %6u  ", loads, stores) << F.getName() << "\n";
            totalLoads += loads;
            totalStores += stores;
        }

        outs() << format("  %5u  %6u  TOTAL\n", totalLoads, totalStores);
        return PreservedAnalyses::all();
    }

    static bool isRequired() { return true; }
};

} // namespace

extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo llvmGetPassPluginInfo() {
    return {LLVM_PLUGIN_API_VERSION, "count-mem-ops", LLVM_VERSION_STRING,
            [](PassBuilder &PB) {
                PB.registerPipelineParsingCallback(
                    [](StringRef Name, ModulePassManager &MPM,
                       ArrayRef<PassBuilder::PipelineElement>) {
                        if (Name == "count-mem-ops") {
                            MPM.addPass(CountMemOps());
                            return true;
                        }
                        return false;
                    });
            }};
}
