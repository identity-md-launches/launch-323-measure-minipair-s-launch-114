// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GasBaselineFixture} from "./GasBaseline.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {MiniPair} from "../src/MiniPair.sol";
import {ReentrantAttacker} from "./mocks/Attackers.sol";

contract MiniPairOptimizationsTest is GasBaselineFixture {
    function test_transientLockBlocksEveryEntryFromAllEthSendingPaths() public {
        ReentrantAttacker attacker = new ReentrantAttacker(pair);
        token.transfer(address(attacker), 10_000_000e18);
        vm.deal(address(this), 100 ether);
        attacker.addLiquidity{value: 10 ether}(INITIAL_TOKEN, 0);

        // All four entry points must share one lock, on all three outgoing ETH paths.
        for (uint256 path; path < 3; ++path) {
            for (uint256 entry = 1; entry <= 4; ++entry) {
                uint256 attempts = attacker.attempts();
                attacker.setMode(ReentrantAttacker.Mode(entry), false);
                if (path == 0) {
                    attacker.addLiquidity{value: 1 ether}(1_000e18, 0);
                } else if (path == 1) {
                    attacker.removeLiquidity(pair.sharesOf(address(attacker)) / 100, 0, 0);
                } else {
                    attacker.swapExactTokensForETH(1_000e18, 0);
                }
                assertEq(attacker.attempts(), attempts + 1);
                assertEq(attacker.lastError(), abi.encodeWithSelector(MiniPair.ReentrancyGuardReentrantCall.selector));
            }
        }
        // A reverted outer call must also roll back the transient lock.
        attacker.setMode(ReentrantAttacker.Mode.AddLiquidity, true);
        vm.expectRevert(MiniPair.EthTransferFailed.selector);
        attacker.swapExactTokensForETH(1_000e18, 0);
        attacker.setMode(ReentrantAttacker.Mode.None, false);
        assertGt(attacker.swapExactTokensForETH(1_000e18, 0), 0);
    }

    function test_cachedSyncMatchesStoredReservesAndEventOrderOnEveryPath() public {
        vm.recordLogs();
        vm.prank(ALICE);
        pair.addLiquidity{value: INITIAL_ETH}(INITIAL_TOKEN, 0);
        _assertSync("LiquidityAdded(address,uint256,uint256,uint256)");

        vm.recordLogs();
        vm.prank(BOB);
        pair.addLiquidity{value: 2 ether}(100_000e18, 0);
        _assertSync("LiquidityAdded(address,uint256,uint256,uint256)");

        vm.recordLogs();
        vm.prank(BOB);
        pair.addLiquidity{value: 1 ether}(200_000e18, 0);
        _assertSync("LiquidityAdded(address,uint256,uint256,uint256)");

        vm.recordLogs();
        vm.prank(BOB);
        pair.swapExactETHForTokens{value: 1 ether}(0);
        _assertSync("Swap(address,uint256,uint256,uint256,uint256)");

        vm.recordLogs();
        vm.prank(BOB);
        pair.swapExactTokensForETH(100_000e18, 0);
        _assertSync("Swap(address,uint256,uint256,uint256,uint256)");

        uint256 shares = pair.sharesOf(BOB);
        vm.recordLogs();
        vm.prank(BOB);
        pair.removeLiquidity(shares, 0, 0);
        _assertSync("LiquidityRemoved(address,uint256,uint256,uint256)");
    }

    function _assertSync(string memory action) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(logs.length, 3);
        assertEq(logs[0].emitter, address(pair));
        assertEq(logs[0].topics[0], keccak256(bytes(action)));
        assertEq(logs[1].emitter, address(pair));
        assertEq(logs[1].topics[0], keccak256("Sync(uint256,uint256)"));
        (uint256 eth, uint256 tokens) = pair.getReserves();
        assertEq(logs[1].data, abi.encode(eth, tokens));
        // The token interaction still follows both pair events.
        assertEq(logs[2].emitter, address(token));
    }

    function test_uncheckedInitialSharesAtMinimumBoundary() public {
        vm.startPrank(ALICE);
        vm.expectRevert(MiniPair.InsufficientInitialLiquidity.selector);
        pair.addLiquidity{value: 1_000}(1_000, 0);
        assertEq(pair.addLiquidity{value: 1_001}(1_001, 1), 1);
        vm.stopPrank();
        assertEq(pair.totalShares(), 1_001);
        assertEq(pair.sharesOf(address(0)), 1_000);
    }

    function test_uncheckedHeldSharesAtBalanceBoundary() public {
        vm.startPrank(ALICE);
        uint256 shares = pair.addLiquidity{value: INITIAL_ETH}(INITIAL_TOKEN, 0);
        vm.expectRevert(abi.encodeWithSelector(MiniPair.InsufficientBalance.selector, shares + 1, shares));
        pair.removeLiquidity(shares + 1, 0, 0);
        pair.removeLiquidity(shares, 0, 0);
        vm.stopPrank();
        assertEq(pair.sharesOf(ALICE), 0);
        assertEq(pair.totalShares(), 1_000);
    }

    function test_reserveAboveUint128RemainsSupported() public {
        // A valid first deposit disproves a uint128 bound even with the launch token.
        uint256 eth = uint256(type(uint128).max) + 1;
        vm.deal(ALICE, eth);
        vm.prank(ALICE);
        pair.addLiquidity{value: eth}(1, 0);
        (uint256 reserveEth, uint256 reserveToken) = pair.getReserves();
        assertEq(reserveEth, eth);
        assertEq(reserveToken, 1);
    }
}
