// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IReserveBalance {
    function dippedIntoReserve() external returns (bool);
}

contract RefundSink {
    receive() external payable {}

    function refund(address payable to, uint256 amount) external {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "refund failed");
    }
}

contract DelegatedDrain {
    IReserveBalance constant RESERVE = IReserveBalance(0x0000000000000000000000000000000000001001);

    receive() external payable {}

    function drainCheckRestore(RefundSink sink, uint256 amount)
        external
        returns (
            bool beforeDip,
            bool duringDip,
            bool afterRestore,
            uint256 beforeBalance,
            uint256 duringBalance,
            uint256 afterBalance
        )
    {
        beforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();

        (bool sent,) = address(sink).call{value: amount}("");
        require(sent, "drain failed");

        duringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();

        sink.refund(payable(address(this)), amount);

        afterBalance = address(this).balance;
        afterRestore = RESERVE.dippedIntoReserve();
    }

    function drainCheckNoRestore(RefundSink sink, uint256 amount)
        external
        returns (bool beforeDip, bool duringDip, uint256 beforeBalance, uint256 duringBalance)
    {
        beforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();

        (bool sent,) = address(sink).call{value: amount}("");
        require(sent, "drain failed");

        duringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();
    }
}
