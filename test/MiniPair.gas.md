# MiniPair optimisation measurements

Baseline: repository commit a3bccbe8ec1cdbee54e8e7eda58e93be9cec8fe5
(launch 114). After: the accompanying source changes. These are local EVM
measurements, not measurements of transactions on Sepolia. The immutable deployment
at 0x898a07c8911f43218c5c2e1b7ae8146026f7e040 was not changed or redeployed.

## Method and results

Reused the unchanged fixtures in GasBaseline.t.sol. Foundry 1.8.3
(cae51ad458f6abb64852b7709eb784352429825d), solc 0.8.26+commit.8a97fa7a;
the repository's Cancun, optimizer 200, non-IR and metadata settings were unchanged.
Preparation occurs in setUp; pair and token are cooled before each measured call.
The initial pool is 10 ETH / 1,000,000 tokens, fee 30 bps; approvals are unlimited.
The fixture has exact output, balance and share assertions.

Gas below is the target call's gross execution gas from vm.lastCallGas(), using
--no-isolate. It excludes the harness, transaction intrinsic/calldata gas and
outer CALL overhead. Every baseline call has a 2,800 gas refund counter; every
optimised call has zero. The last column subtracts that lost refund from gross
savings (assuming the refund can be fully applied); it is not a transaction receipt.

| Call | Before gross | After gross | Gross saved | Saved after refund |
| --- | ---: | ---: | ---: | ---: |
| swapExactETHForTokens (1 ETH) | 36,685 | 31,655 | 5,030 | 2,230 |
| swapExactTokensForETH (100,000 tokens) | 48,116 | 43,086 | 5,030 | 2,230 |
| First addLiquidity (10 ETH, 1,000,000 tokens) | 159,451 | 154,318 | 5,133 | 2,333 |
| Later addLiquidity, refund (2 ETH, 100,000 tokens) | 76,215 | 71,150 | 5,065 | 2,265 |
| Later addLiquidity, fewer tokens (1 ETH, 200,000 offered) | 69,084 | 64,019 | 5,065 | 2,265 |
| removeLiquidity (half the initial provider's shares) | 53,802 | 48,673 | 5,129 | 2,329 |

| Size in bytes | Before | After | Change |
| --- | ---: | ---: | ---: |
| Runtime | 4,997 | 4,998 | +1 |
| Creation bytecode, excluding constructor arguments | 5,288 | 5,285 | -3 |
| Deployment initcode, including two 32-byte constructor arguments | 5,352 | 5,349 | -3 |

## Changes and limits

- Replaced the persistent OpenZeppelin lock with a Cancun transient lock shared by
  all four mutating entry points. Kept ReentrancyGuardReentrantCall() exactly.
  Transient slot 0 is used only by this lock; it is separate from persistent
  storage. Successful calls clear it, and reverting calls roll its writes back.
  This source requires Cancun, as already specified by the project.
- Sync uses the new reserve values already calculated, without rereading storage.
  Event order, payloads and effects-before-interactions remain unchanged.
- Only initial - MINIMUM_SHARES and held - shares are unchecked. Their existing
  explicit checks prove each subtraction safe; comments sit beside the operations.
  All other arithmetic, including overflow-sensitive quote calculations, remains
  checked as before.
- Rejected uint128 packing: the constructor accepts arbitrary tokens and no
  uint128 bound is enforced on either reserve. Even with MSWAP, a first deposit
  of 2^128 wei and one token base unit passes the existing multiplication and
  minimum-share checks in the EVM. A cap or narrowing cast would change behavior.
  The added boundary regression preserves this accepted case. Realistic balances
  are not a proof of the contract's input bounds.
- No deployment, configuration, dependency, token contract or existing test changed.
  No new source dependency is required.

## Regression checks and reproduction

MiniPair.optimizations.t.sol adds five tests:
1. All four reentrant entry points fail with the exact guard error through each
   of the three ETH-sending paths (12 combinations). Sequential successful calls
   and a successful call after a reverted ETH send also check lock cleanup.
2. All six measured paths emit the action event then Sync with the exact stored
   reserves, before the token interaction.
3. First deposits at and immediately above the minimum square-root boundary.
4. Removal above the held balance still reverts; exact full removal reaches zero.
5. Reserves above uint128 remain representable.

Full suite: 112 passed, zero failed or skipped, including the unchanged
MiniPair.t.sol, MiniPair.invariant.t.sol and MiniSwapToken.t.sol. Existing fuzz and
invariant settings were retained. Formatting of changed Solidity and git diff
--check passed. The before/after compiled ABI equals docs/abi/MiniPair.json;
its canonical keccak256 remains
0x1e3527a04b6c51b781761bb57bf859b9e4edfc4b89c258ad0fdb54d9dd608f64,
matching docs/abi-hashes.json.

With the pinned compiler already installed, run:

```sh
forge test --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache \
  --match-path test/GasBaseline.t.sol --match-contract 'MiniPair.*GasTest' --no-isolate -vv
forge inspect MiniPair bytecode --out test/scratch/out --cache-path test/scratch/cache
forge inspect MiniPair deployedBytecode --out test/scratch/out --cache-path test/scratch/cache
```

Count hex bytes after the 0x prefix for sizes; add 64 to creation bytecode for
constructor arguments. Run the same measurements at the baseline commit to
reproduce the before column. This environment lacked cached solc, so local runs
used the official solc-bin 0.8.26 binary in test/scratch with
--use test/scratch/solc-0.8.26. That compiler is build tooling, not a new contract
dependency; scratch artifacts are not part of the deliverable.
