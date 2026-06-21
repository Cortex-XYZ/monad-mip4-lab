// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReserveBalance {
	function dippedIntoReserve() external returns (bool);
}

contract ReserveProbe {
	address constant RESERVE_BALANCE = address(0x1001);

	function probe() external returns (bool) {
		return IReserveBalance(RESERVE_BALANCE).dippedIntoReserve();
	}
}
