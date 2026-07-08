// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Mip4Account} from "../src/Mip4Account.sol";
import {Simple7702Account} from "@account-abstraction/accounts/Simple7702Account.sol";
import {BaseAccount} from "@account-abstraction/core/BaseAccount.sol";
import {PackedUserOperation} from "@account-abstraction/interfaces/PackedUserOperation.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// Account-level tests provable under `forge test` (no dip tracking needed):
/// access control, batch behavior, ERC-1271, userop signature validation,
/// and differential no-dip parity with the stock Simple7702Account.
/// Dip semantics through the account are covered by the anvil suite.
contract Mip4AccountTest is Test {
    address constant ENTRY_POINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    Mip4Account impl;
    Simple7702Account stockImpl;

    address eoa;
    uint256 eoaKey;
    address stockEoa;
    address payable recipient;

    function setUp() public {
        impl = new Mip4Account();
        stockImpl = new Simple7702Account();

        (eoa, eoaKey) = makeAddrAndKey("eoa");
        stockEoa = makeAddr("stockEoa");
        recipient = payable(makeAddr("recipient"));

        vm.etch(eoa, abi.encodePacked(hex"ef0100", address(impl)));
        vm.etch(stockEoa, abi.encodePacked(hex"ef0100", address(stockImpl)));
        vm.deal(eoa, 10.5 ether);
        vm.deal(stockEoa, 10.5 ether);
    }

    function _account() internal view returns (Mip4Account) {
        return Mip4Account(payable(eoa));
    }

    // --- access control ---

    function test_execute_fromEntryPoint() public {
        vm.prank(ENTRY_POINT);
        _account().execute(recipient, 0.1 ether, "");
        assertEq(recipient.balance, 0.1 ether);
    }

    function test_execute_fromSelf() public {
        vm.prank(eoa);
        _account().execute(recipient, 0.1 ether, "");
        assertEq(recipient.balance, 0.1 ether);
    }

    function test_execute_fromStranger_reverts() public {
        vm.prank(makeAddr("stranger"));
        vm.expectRevert("not from self or EntryPoint");
        _account().execute(recipient, 0.1 ether, "");
    }

    function test_executeBatch_fromStranger_reverts() public {
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](1);
        calls[0] = BaseAccount.Call(recipient, 0.1 ether, "");
        vm.prank(makeAddr("stranger"));
        vm.expectRevert("not from self or EntryPoint");
        _account().executeBatch(calls);
    }

    // --- execution behavior ---

    function test_executeBatch_multipleCalls() public {
        address payable recipient2 = payable(makeAddr("recipient2"));
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call(recipient, 0.1 ether, "");
        calls[1] = BaseAccount.Call(recipient2, 0.2 ether, "");

        vm.prank(ENTRY_POINT);
        _account().executeBatch(calls);

        assertEq(recipient.balance, 0.1 ether);
        assertEq(recipient2.balance, 0.2 ether);
        assertEq(eoa.balance, 10.2 ether);
    }

    function test_executeBatch_failingCall_revertsWithIndex() public {
        BaseAccount.Call[] memory calls = new BaseAccount.Call[](2);
        calls[0] = BaseAccount.Call(recipient, 0.1 ether, "");
        calls[1] = BaseAccount.Call(address(this), 0, abi.encodeWithSignature("alwaysReverts()"));

        vm.prank(ENTRY_POINT);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseAccount.ExecuteError.selector, 1, abi.encodeWithSignature("Error(string)", "nope")
            )
        );
        _account().executeBatch(calls);
    }

    function alwaysReverts() external pure {
        revert("nope");
    }

    function test_execute_bubblesTargetRevert() public {
        vm.prank(ENTRY_POINT);
        vm.expectRevert(bytes("nope"));
        _account().execute(address(this), 0, abi.encodeWithSignature("alwaysReverts()"));
    }

    // --- signatures ---

    function test_isValidSignature_ownerKey() public view {
        bytes32 digest = keccak256("hello monad");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaKey, digest);
        bytes4 magic = _account().isValidSignature(digest, abi.encodePacked(r, s, v));
        assertEq(magic, IERC1271.isValidSignature.selector);
    }

    function test_isValidSignature_wrongKey() public {
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        bytes32 digest = keccak256("hello monad");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes4 magic = _account().isValidSignature(digest, abi.encodePacked(r, s, v));
        assertEq(magic, bytes4(0xffffffff));
    }

    function test_validateUserOp_signatureCheck() public {
        PackedUserOperation memory op;
        op.sender = eoa;
        bytes32 userOpHash = keccak256("op");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaKey, userOpHash);
        op.signature = abi.encodePacked(r, s, v);

        vm.prank(ENTRY_POINT);
        uint256 validationData = _account().validateUserOp(op, userOpHash, 0);
        assertEq(validationData, 0); // SIG_VALIDATION_SUCCESS

        // wrong signer -> SIG_VALIDATION_FAILED (1), not a revert
        (, uint256 wrongKey) = makeAddrAndKey("wrong");
        (v, r, s) = vm.sign(wrongKey, userOpHash);
        op.signature = abi.encodePacked(r, s, v);
        vm.prank(ENTRY_POINT);
        validationData = _account().validateUserOp(op, userOpHash, 0);
        assertEq(validationData, 1);
    }

    function test_validateUserOp_notEntryPoint_reverts() public {
        PackedUserOperation memory op;
        op.sender = eoa;
        vm.expectRevert("account: not from EntryPoint");
        _account().validateUserOp(op, bytes32(0), 0);
    }

    // --- interfaces / receive ---

    function test_supportsInterface() public view {
        assertTrue(_account().supportsInterface(type(IERC1271).interfaceId));
    }

    function test_receivesPlainTransfers() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = payable(eoa).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(eoa.balance, 11 ether);
    }

    // --- differential parity with stock Simple7702Account (no-dip path) ---

    function test_differential_execute_matchesStockAccount() public {
        address payable r1 = payable(makeAddr("diff1"));
        address payable r2 = payable(makeAddr("diff2"));

        vm.prank(ENTRY_POINT);
        Mip4Account(payable(eoa)).execute(r1, 0.3 ether, "");
        vm.prank(ENTRY_POINT);
        Simple7702Account(payable(stockEoa)).execute(r2, 0.3 ether, "");

        assertEq(r1.balance, r2.balance);
        assertEq(eoa.balance, stockEoa.balance);
    }

    function test_differential_executeBatch_matchesStockAccount() public {
        address payable r1 = payable(makeAddr("diffB1"));
        address payable r2 = payable(makeAddr("diffB2"));

        BaseAccount.Call[] memory calls1 = new BaseAccount.Call[](2);
        calls1[0] = BaseAccount.Call(r1, 0.1 ether, "");
        calls1[1] = BaseAccount.Call(r1, 0.2 ether, "");
        BaseAccount.Call[] memory calls2 = new BaseAccount.Call[](2);
        calls2[0] = BaseAccount.Call(r2, 0.1 ether, "");
        calls2[1] = BaseAccount.Call(r2, 0.2 ether, "");

        vm.prank(ENTRY_POINT);
        Mip4Account(payable(eoa)).executeBatch(calls1);
        vm.prank(ENTRY_POINT);
        Simple7702Account(payable(stockEoa)).executeBatch(calls2);

        assertEq(r1.balance, r2.balance);
        assertEq(eoa.balance, stockEoa.balance);
    }
}
