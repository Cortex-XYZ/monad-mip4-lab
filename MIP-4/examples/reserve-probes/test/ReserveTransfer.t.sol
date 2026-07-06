// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ReserveTransfer} from "../src/ReserveTransfer.sol";

contract ReserveTransferTest is Test {
    ReserveTransfer transferProbe;

    address alice = address(0xA11CE);
    address payable receiver = payable(address(0xB0B));

    function setUp() public {
        transferProbe = new ReserveTransfer();
    }

    function testTransferAndCheckReserveState() public {
        vm.deal(alice, 11 ether);

        vm.prank(alice);
        bool dipped = transferProbe.sendAndCheck{value: 2 ether}(receiver);

        emit log_named_uint("alice balance", alice.balance);
        emit log_named_uint("receiver balance", receiver.balance);
        emit log_named_string("dipped", dipped ? "true" : "false");
    }

    function testDoubleTransferAndCheckReserveState() public {
        address payable receiver1 = payable(address(0xB0B));
        address payable receiver2 = payable(address(0xCAFE));

        vm.deal(alice, 11 ether);

        vm.prank(alice);
        bool dipped = transferProbe.doubleSendAndCheck{value: 2 ether}(
            receiver1,
            receiver2
        );

        emit log_named_uint("alice balance", alice.balance);
        emit log_named_uint("receiver1 balance", receiver1.balance);
        emit log_named_uint("receiver2 balance", receiver2.balance);
        emit log_named_string("dipped", dipped ? "true" : "false");
    }
}
