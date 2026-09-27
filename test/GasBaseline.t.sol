// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MiniPair} from "../src/MiniPair.sol";
import {MiniSwapToken} from "../src/MiniSwapToken.sol";

/// @dev Keep preparation in setUp so measured calls modify clean storage. Each test
/// logs the target call's gross gas and refund counter; .gas-snapshot also includes
/// the test harness and assertions. Use --no-isolate for callee execution gas and
/// --isolate for transaction accounting. No gas ceiling is asserted.
abstract contract GasBaselineFixture is Test {
    uint256 internal constant INITIAL_ETH = 10 ether;
    uint256 internal constant INITIAL_TOKEN = 1_000_000e18;
    uint256 internal constant FUNDS = 100_000_000e18;
    uint256 internal constant SEED_SHARES = 3_162_277_660_168_379_331_998;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);

    MiniSwapToken internal token;
    MiniPair internal pair;

    function setUp() public virtual {
        token = new MiniSwapToken();
        pair = new MiniPair(address(token), 30);
        vm.deal(ALICE, 1_000 ether);
        vm.deal(BOB, 1_000 ether);
        token.transfer(ALICE, FUNDS);
        token.transfer(BOB, FUNDS);
        vm.prank(ALICE);
        token.approve(address(pair), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(pair), type(uint256).max);
    }

    function _cold(address caller) internal {
        // An EOA transaction sender is warm, including when receiving an ETH payout.
        assertGt(caller.balance, 0);
        vm.cool(address(pair));
        vm.cool(address(token));
        vm.prank(caller);
    }

    function _record(string memory name) internal {
        Vm.Gas memory usage = vm.lastCallGas();
        emit log_named_uint(name, usage.gasTotalUsed);
        emit log_named_int(string.concat(name, ".refund"), usage.gasRefunded);
    }

    function _assertReserves(uint256 eth, uint256 tokens) internal view {
        (uint256 actualEth, uint256 actualTokens) = pair.getReserves();
        assertEq(actualEth, eth);
        assertEq(actualTokens, tokens);
        assertEq(address(pair).balance, eth);
        assertEq(token.balanceOf(address(pair)), tokens);
    }

    function _quote(uint256 amount, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        return amount * 9_970 * reserveOut / (reserveIn * 10_000 + amount * 9_970);
    }
}

contract MiniPairFirstLiquidityGasTest is GasBaselineFixture {
    function testGas_addLiquidity_first() public {
        _cold(ALICE);
        uint256 shares = pair.addLiquidity{value: INITIAL_ETH}(INITIAL_TOKEN, SEED_SHARES - 1_000);
        _record("MiniPair.addLiquidity_first");
        assertEq(shares, Math.sqrt(INITIAL_ETH * INITIAL_TOKEN) - 1_000);
        assertEq(pair.totalShares(), SEED_SHARES);
        assertEq(pair.sharesOf(address(0)), 1_000);
        assertEq(pair.sharesOf(ALICE), shares);
        assertEq(token.balanceOf(ALICE), FUNDS - INITIAL_TOKEN);
        _assertReserves(INITIAL_ETH, INITIAL_TOKEN);
    }
}

contract MiniPairGasTest is GasBaselineFixture {
    function setUp() public override {
        super.setUp();
        vm.prank(ALICE);
        pair.addLiquidity{value: INITIAL_ETH}(INITIAL_TOKEN, 0);
    }

    function testGas_swapExactETHForTokens() public {
        uint256 expected = _quote(1 ether, INITIAL_ETH, INITIAL_TOKEN);
        _cold(BOB);
        uint256 out = pair.swapExactETHForTokens{value: 1 ether}(expected);
        _record("MiniPair.swapExactETHForTokens");
        assertEq(out, expected);
        assertEq(token.balanceOf(BOB), FUNDS + out);
        _assertReserves(INITIAL_ETH + 1 ether, INITIAL_TOKEN - out);
    }

    function testGas_swapExactTokensForETH() public {
        uint256 amount = 100_000e18;
        uint256 expected = _quote(amount, INITIAL_TOKEN, INITIAL_ETH);
        _cold(BOB);
        uint256 out = pair.swapExactTokensForETH(amount, expected);
        _record("MiniPair.swapExactTokensForETH");
        assertEq(out, expected);
        assertEq(BOB.balance, 1_000 ether + out);
        assertEq(token.balanceOf(BOB), FUNDS - amount);
        _assertReserves(INITIAL_ETH - out, INITIAL_TOKEN + amount);
    }

    function testGas_addLiquidity_refundsETH() public {
        _cold(BOB);
        uint256 shares = pair.addLiquidity{value: 2 ether}(100_000e18, SEED_SHARES / 10);
        _record("MiniPair.addLiquidity_refundsETH");
        assertEq(shares, SEED_SHARES / 10);
        assertEq(pair.sharesOf(BOB), shares);
        assertEq(pair.totalShares(), SEED_SHARES + shares);
        assertEq(BOB.balance, 999 ether);
        assertEq(token.balanceOf(BOB), FUNDS - 100_000e18);
        _assertReserves(11 ether, 1_100_000e18);
    }

    function testGas_addLiquidity_pullsFewerTokens() public {
        _cold(BOB);
        uint256 shares = pair.addLiquidity{value: 1 ether}(200_000e18, SEED_SHARES / 10);
        _record("MiniPair.addLiquidity_pullsFewerTokens");
        assertEq(shares, SEED_SHARES / 10);
        assertEq(pair.sharesOf(BOB), shares);
        assertEq(pair.totalShares(), SEED_SHARES + shares);
        assertEq(BOB.balance, 999 ether);
        assertEq(token.balanceOf(BOB), FUNDS - 100_000e18);
        _assertReserves(11 ether, 1_100_000e18);
    }

    function testGas_removeLiquidity() public {
        uint256 burned = (SEED_SHARES - 1_000) / 2;
        uint256 expectedEth = burned * INITIAL_ETH / SEED_SHARES;
        uint256 expectedToken = burned * INITIAL_TOKEN / SEED_SHARES;
        _cold(ALICE);
        (uint256 ethOut, uint256 tokenOut) = pair.removeLiquidity(burned, expectedEth, expectedToken);
        _record("MiniPair.removeLiquidity");
        assertEq(ethOut, expectedEth);
        assertEq(tokenOut, expectedToken);
        assertEq(ALICE.balance, 990 ether + ethOut);
        assertEq(token.balanceOf(ALICE), FUNDS - INITIAL_TOKEN + tokenOut);
        assertEq(pair.sharesOf(ALICE), SEED_SHARES - 1_000 - burned);
        assertEq(pair.totalShares(), SEED_SHARES - burned);
        _assertReserves(INITIAL_ETH - ethOut, INITIAL_TOKEN - tokenOut);
    }

    function testGas_BPS() public {
        _cold(BOB);
        uint256 result = pair.BPS();
        _record("MiniPair.BPS");
        assertEq(result, 10_000);
    }

    function testGas_MAX_FEE_BPS() public {
        _cold(BOB);
        uint256 result = pair.MAX_FEE_BPS();
        _record("MiniPair.MAX_FEE_BPS");
        assertEq(result, 1_000);
    }

    function testGas_MINIMUM_SHARES() public {
        _cold(BOB);
        uint256 result = pair.MINIMUM_SHARES();
        _record("MiniPair.MINIMUM_SHARES");
        assertEq(result, 1_000);
    }

    function testGas_token() public {
        _cold(BOB);
        address result = address(pair.token());
        _record("MiniPair.token");
        assertEq(result, address(token));
    }

    function testGas_feeBps() public {
        _cold(BOB);
        uint256 result = pair.feeBps();
        _record("MiniPair.feeBps");
        assertEq(result, 30);
    }

    function testGas_totalShares() public {
        _cold(BOB);
        uint256 result = pair.totalShares();
        _record("MiniPair.totalShares");
        assertEq(result, SEED_SHARES);
    }

    function testGas_sharesOf() public {
        _cold(BOB);
        uint256 result = pair.sharesOf(ALICE);
        _record("MiniPair.sharesOf");
        assertEq(result, SEED_SHARES - 1_000);
    }

    function testGas_getReserves() public {
        _cold(BOB);
        (uint256 eth, uint256 tokens) = pair.getReserves();
        _record("MiniPair.getReserves");
        assertEq(eth, INITIAL_ETH);
        assertEq(tokens, INITIAL_TOKEN);
    }

    function testGas_quoteEthToToken() public {
        _cold(BOB);
        uint256 result = pair.quoteEthToToken(1 ether);
        _record("MiniPair.quoteEthToToken");
        assertEq(result, _quote(1 ether, INITIAL_ETH, INITIAL_TOKEN));
    }

    function testGas_quoteTokenToEth() public {
        _cold(BOB);
        uint256 result = pair.quoteTokenToEth(100_000e18);
        _record("MiniPair.quoteTokenToEth");
        assertEq(result, _quote(100_000e18, INITIAL_TOKEN, INITIAL_ETH));
    }
}

contract MiniSwapTokenGasTest is GasBaselineFixture {
    function setUp() public override {
        super.setUp();
        vm.prank(ALICE);
        token.approve(BOB, 1_000e18);
        vm.prank(ALICE);
        token.approve(CAROL, type(uint256).max);
    }

    function testGas_TOTAL_SUPPLY() public {
        _cold(BOB);
        uint256 result = token.TOTAL_SUPPLY();
        _record("MiniSwapToken.TOTAL_SUPPLY");
        assertEq(result, 1e27);
    }

    function testGas_name() public {
        _cold(BOB);
        string memory result = token.name();
        _record("MiniSwapToken.name");
        assertEq(result, "Mini Swap");
    }

    function testGas_symbol() public {
        _cold(BOB);
        string memory result = token.symbol();
        _record("MiniSwapToken.symbol");
        assertEq(result, "MSWAP");
    }

    function testGas_decimals() public {
        _cold(BOB);
        uint8 result = token.decimals();
        _record("MiniSwapToken.decimals");
        assertEq(result, 18);
    }

    function testGas_totalSupply() public {
        _cold(BOB);
        uint256 result = token.totalSupply();
        _record("MiniSwapToken.totalSupply");
        assertEq(result, 1e27);
    }

    function testGas_balanceOf() public {
        _cold(BOB);
        uint256 result = token.balanceOf(ALICE);
        _record("MiniSwapToken.balanceOf");
        assertEq(result, FUNDS);
    }

    function testGas_allowance() public {
        _cold(BOB);
        uint256 result = token.allowance(ALICE, BOB);
        _record("MiniSwapToken.allowance");
        assertEq(result, 1_000e18);
    }

    function testGas_approve() public {
        _cold(BOB);
        bool result = token.approve(ALICE, 1_000e18);
        _record("MiniSwapToken.approve");
        assertTrue(result);
        assertEq(token.allowance(BOB, ALICE), 1_000e18);
    }

    function testGas_transfer_existingRecipient() public {
        _cold(ALICE);
        bool result = token.transfer(BOB, 100e18);
        _record("MiniSwapToken.transfer_existingRecipient");
        assertTrue(result);
        assertEq(token.balanceOf(ALICE), FUNDS - 100e18);
        assertEq(token.balanceOf(BOB), FUNDS + 100e18);
    }

    function testGas_transfer_newRecipient() public {
        _cold(ALICE);
        bool result = token.transfer(CAROL, 100e18);
        _record("MiniSwapToken.transfer_newRecipient");
        assertTrue(result);
        assertEq(token.balanceOf(ALICE), FUNDS - 100e18);
        assertEq(token.balanceOf(CAROL), 100e18);
    }

    function testGas_transferFrom_finiteAllowance() public {
        _cold(BOB);
        bool result = token.transferFrom(ALICE, BOB, 100e18);
        _record("MiniSwapToken.transferFrom_finiteAllowance");
        assertTrue(result);
        assertEq(token.allowance(ALICE, BOB), 900e18);
        assertEq(token.balanceOf(ALICE), FUNDS - 100e18);
        assertEq(token.balanceOf(BOB), FUNDS + 100e18);
    }

    function testGas_transferFrom_infiniteAllowance() public {
        // CAROL is the spender; BOB already has a nonzero token balance.
        vm.deal(CAROL, 1 ether);
        _cold(CAROL);
        bool result = token.transferFrom(ALICE, BOB, 100e18);
        _record("MiniSwapToken.transferFrom_infiniteAllowance");
        assertTrue(result);
        assertEq(token.allowance(ALICE, CAROL), type(uint256).max);
        assertEq(token.balanceOf(ALICE), FUNDS - 100e18);
        assertEq(token.balanceOf(BOB), FUNDS + 100e18);
    }
}
