// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReserveBalanceCheck {
    function dippedIntoReserve() external returns (bool);
}

contract ReserveTransfer {
    address constant RESERVE_BALANCE = address(0x1001);

    function check() public returns (bool) {
        return IReserveBalanceCheck(RESERVE_BALANCE).dippedIntoReserve();
    }

    function sendAndCheck(address payable receiver) external payable returns (bool) {
        (bool ok, ) = receiver.call{value: msg.value}("");
        require(ok, "transfer failed");

        return check();
    }

    function doubleSendAndCheck(
        address payable receiver1,
        address payable receiver2
    ) external payable returns (bool) {
        require(msg.value == 2 ether, "send exactly 2 MON");

        (bool ok1, ) = receiver1.call{value: 1 ether}("");
        require(ok1, "first transfer failed");

        bool afterFirst = check();

        (bool ok2, ) = receiver2.call{value: 1 ether}("");
        require(ok2, "second transfer failed");

        bool afterSecond = check();

        return afterFirst || afterSecond;
    }
}
