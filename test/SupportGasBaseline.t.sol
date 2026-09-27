// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GasBaselineFixture} from "./GasBaseline.t.sol";
import {MiniPair} from "../src/MiniPair.sol";
import {ReentrantAttacker, RejectingReceiver, FeeOnTransferToken} from "./mocks/Attackers.sol";

// Support contracts are reported separately from the two launch contracts.
contract FeeOnTransferTokenGasTest is GasBaselineFixture {
    FeeOnTransferToken internal feeToken;

    function setUp() public override {
        super.setUp();
        feeToken = new FeeOnTransferToken();
        feeToken.transfer(ALICE, 10_000e18);
        vm.prank(ALICE);
        feeToken.approve(BOB, 1_000e18);
    }

    function _prepare(address caller) internal {
        vm.cool(address(feeToken));
        _cold(caller);
    }

    function testGas_name() public {
        _prepare(BOB);
        string memory result = feeToken.name();
        _record("FeeOnTransferToken.name");
        assertEq(result, "Fee Token");
    }

    function testGas_symbol() public {
        _prepare(BOB);
        string memory result = feeToken.symbol();
        _record("FeeOnTransferToken.symbol");
        assertEq(result, "FEE");
    }

    function testGas_decimals() public {
        _prepare(BOB);
        uint8 result = feeToken.decimals();
        _record("FeeOnTransferToken.decimals");
        assertEq(result, 18);
    }

    function testGas_totalSupply() public {
        _prepare(BOB);
        uint256 result = feeToken.totalSupply();
        _record("FeeOnTransferToken.totalSupply");
        assertEq(result, 999_900e18);
    }

    function testGas_balanceOf() public {
        _prepare(BOB);
        uint256 result = feeToken.balanceOf(ALICE);
        _record("FeeOnTransferToken.balanceOf");
        assertEq(result, 9_900e18);
    }

    function testGas_allowance() public {
        _prepare(BOB);
        uint256 result = feeToken.allowance(ALICE, BOB);
        _record("FeeOnTransferToken.allowance");
        assertEq(result, 1_000e18);
    }

    function testGas_approve() public {
        _prepare(BOB);
        bool result = feeToken.approve(ALICE, 100e18);
        _record("FeeOnTransferToken.approve");
        assertTrue(result);
        assertEq(feeToken.allowance(BOB, ALICE), 100e18);
    }

    function testGas_transfer() public {
        _prepare(ALICE);
        bool result = feeToken.transfer(BOB, 100e18);
        _record("FeeOnTransferToken.transfer");
        assertTrue(result);
        assertEq(feeToken.balanceOf(BOB), 99e18);
        assertEq(feeToken.totalSupply(), 999_899e18);
    }

    function testGas_transferFrom() public {
        _prepare(BOB);
        bool result = feeToken.transferFrom(ALICE, BOB, 100e18);
        _record("FeeOnTransferToken.transferFrom");
        assertTrue(result);
        assertEq(feeToken.balanceOf(BOB), 99e18);
        assertEq(feeToken.allowance(ALICE, BOB), 900e18);
    }
}

contract ReentrantAttackerGasTest is GasBaselineFixture {
    ReentrantAttacker internal attacker;

    function setUp() public override {
        super.setUp();
        attacker = new ReentrantAttacker(pair);
        token.transfer(address(attacker), 1_000_000e18);
        vm.deal(address(this), 100 ether);
        vm.deal(address(attacker), 10 ether);
        attacker.addLiquidity{value: 1 ether}(100_000e18, 0);
    }

    function _prepare(address caller) internal {
        vm.cool(address(attacker));
        _cold(caller);
    }

    function testGas_pair() public {
        _prepare(BOB);
        address result = address(attacker.pair());
        _record("ReentrantAttacker.pair");
        assertEq(result, address(pair));
    }

    function testGas_token() public {
        _prepare(BOB);
        address result = address(attacker.token());
        _record("ReentrantAttacker.token");
        assertEq(result, address(token));
    }

    function testGas_mode() public {
        _prepare(BOB);
        ReentrantAttacker.Mode result = attacker.mode();
        _record("ReentrantAttacker.mode");
        assertEq(uint256(result), uint256(ReentrantAttacker.Mode.None));
    }

    function testGas_bubble() public {
        _prepare(BOB);
        bool result = attacker.bubble();
        _record("ReentrantAttacker.bubble");
        assertFalse(result);
    }

    function testGas_attempts() public {
        _prepare(BOB);
        uint256 result = attacker.attempts();
        _record("ReentrantAttacker.attempts");
        assertEq(result, 0);
    }

    function testGas_lastError() public {
        _prepare(BOB);
        bytes memory result = attacker.lastError();
        _record("ReentrantAttacker.lastError");
        assertEq(result.length, 0);
    }

    function testGas_setMode() public {
        _prepare(BOB);
        attacker.setMode(ReentrantAttacker.Mode.RemoveLiquidity, true);
        _record("ReentrantAttacker.setMode");
        assertTrue(attacker.bubble());
        assertEq(uint256(attacker.mode()), uint256(ReentrantAttacker.Mode.RemoveLiquidity));
    }

    function testGas_addLiquidity() public {
        _prepare(BOB);
        uint256 shares = attacker.addLiquidity{value: 1 ether}(100_000e18, 0);
        _record("ReentrantAttacker.addLiquidity");
        assertGt(shares, 0);
        _assertReserves(2 ether, 200_000e18);
    }

    function testGas_removeLiquidity() public {
        uint256 shares = pair.sharesOf(address(attacker)) / 2;
        _prepare(BOB);
        (uint256 ethOut, uint256 tokenOut) = attacker.removeLiquidity(shares, 0, 0);
        _record("ReentrantAttacker.removeLiquidity");
        assertGt(ethOut, 0);
        assertGt(tokenOut, 0);
        _assertReserves(1 ether - ethOut, 100_000e18 - tokenOut);
    }

    function testGas_swapExactTokensForETH() public {
        _prepare(BOB);
        uint256 out = attacker.swapExactTokensForETH(10_000e18, 0);
        _record("ReentrantAttacker.swapExactTokensForETH");
        assertEq(out, _quote(10_000e18, 100_000e18, 1 ether));
    }

    function testGas_reenter() public {
        _prepare(address(attacker));
        attacker.reenter(ReentrantAttacker.Mode.None);
        _record("ReentrantAttacker.reenter");
        assertEq(attacker.attempts(), 0);
    }

    function testGas_receive() public {
        _prepare(BOB);
        (bool ok,) = address(attacker).call{value: 1 wei}("");
        _record("ReentrantAttacker.receive");
        assertTrue(ok);
        assertEq(address(attacker).balance, 10 ether + 1);
    }
}

contract RejectingReceiverGasTest is GasBaselineFixture {
    RejectingReceiver internal receiver;

    function setUp() public override {
        super.setUp();
        receiver = new RejectingReceiver(pair);
        token.transfer(address(receiver), 1_000_000e18);
        vm.deal(address(this), 100 ether);
        receiver.addLiquidity{value: 1 ether}(100_000e18, 0);
    }

    function _prepare() internal {
        vm.cool(address(receiver));
        _cold(BOB);
    }

    function testGas_pair() public {
        _prepare();
        address result = address(receiver.pair());
        _record("RejectingReceiver.pair");
        assertEq(result, address(pair));
    }

    function testGas_addLiquidity() public {
        _prepare();
        uint256 shares = receiver.addLiquidity{value: 1 ether}(100_000e18, 0);
        _record("RejectingReceiver.addLiquidity");
        assertGt(shares, 0);
        _assertReserves(2 ether, 200_000e18);
    }

    function testGas_removeLiquidity_reverts() public {
        uint256 shares = pair.sharesOf(address(receiver)) / 2;
        _prepare();
        (bool ok, bytes memory reason) = address(receiver).call(abi.encodeCall(receiver.removeLiquidity, (shares)));
        _record("RejectingReceiver.removeLiquidity_reverts");
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(MiniPair.EthTransferFailed.selector));
        _assertReserves(1 ether, 100_000e18);
    }

    function testGas_swapExactTokensForETH_reverts() public {
        _prepare();
        (bool ok, bytes memory reason) =
            address(receiver).call(abi.encodeCall(receiver.swapExactTokensForETH, (10_000e18)));
        _record("RejectingReceiver.swapExactTokensForETH_reverts");
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(MiniPair.EthTransferFailed.selector));
        _assertReserves(1 ether, 100_000e18);
    }

    function testGas_receive_reverts() public {
        _prepare();
        (bool ok, bytes memory reason) = address(receiver).call{value: 1 wei}("");
        _record("RejectingReceiver.receive_reverts");
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSignature("Error(string)", "no ETH accepted"));
    }
}
