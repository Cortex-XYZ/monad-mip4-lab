// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IReserveBalance {
    function dippedIntoReserve() external returns (bool);
}

contract TestnetRefundSink {
    receive() external payable {}

    function refund(address payable to, uint256 amount) external {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "refund failed");
    }
}

contract TestnetDelegatedProbe {
    IReserveBalance constant RESERVE =
        IReserveBalance(0x0000000000000000000000000000000000001001);

    bool public lastBeforeDip;
    bool public lastDuringDip;
    bool public lastAfterDip;

    uint256 public lastBeforeBalance;
    uint256 public lastDuringBalance;
    uint256 public lastAfterBalance;

    event ProbeResult(
        string label,
        address self,
        address caller,
        uint256 balance,
        bool dipped
    );

    receive() external payable {}

    function probeNoop()
        external
        returns (bool beforeDip, bool duringDip, bool afterDip)
    {
        lastBeforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();
        lastBeforeDip = beforeDip;

        emit ProbeResult(
            "before",
            address(this),
            msg.sender,
            lastBeforeBalance,
            beforeDip
        );

        lastDuringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();
        lastDuringDip = duringDip;

        emit ProbeResult(
            "during",
            address(this),
            msg.sender,
            lastDuringBalance,
            duringDip
        );

        lastAfterBalance = address(this).balance;
        afterDip = RESERVE.dippedIntoReserve();
        lastAfterDip = afterDip;

        emit ProbeResult(
            "after",
            address(this),
            msg.sender,
            lastAfterBalance,
            afterDip
        );
    }

    function probeDrainRestore(
        TestnetRefundSink sink,
        uint256 amount
    ) external returns (bool beforeDip, bool duringDip, bool afterDip) {
        lastBeforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();
        lastBeforeDip = beforeDip;

        emit ProbeResult(
            "before",
            address(this),
            msg.sender,
            lastBeforeBalance,
            beforeDip
        );

        (bool sent,) = address(sink).call{value: amount}("");
        require(sent, "drain failed");

        lastDuringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();
        lastDuringDip = duringDip;

        emit ProbeResult(
            "during",
            address(this),
            msg.sender,
            lastDuringBalance,
            duringDip
        );

        sink.refund(payable(address(this)), amount);

        lastAfterBalance = address(this).balance;
        afterDip = RESERVE.dippedIntoReserve();
        lastAfterDip = afterDip;

        emit ProbeResult(
            "after",
            address(this),
            msg.sender,
            lastAfterBalance,
            afterDip
        );
    }

    function probeDrainNoRestore(
        TestnetRefundSink sink,
        uint256 amount
    ) external returns (bool beforeDip, bool duringDip, bool afterDip) {
        lastBeforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();
        lastBeforeDip = beforeDip;

        emit ProbeResult(
            "before",
            address(this),
            msg.sender,
            lastBeforeBalance,
            beforeDip
        );

        (bool sent,) = address(sink).call{value: amount}("");
        require(sent, "drain failed");

        lastDuringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();
        lastDuringDip = duringDip;

        emit ProbeResult(
            "during",
            address(this),
            msg.sender,
            lastDuringBalance,
            duringDip
        );

        lastAfterBalance = address(this).balance;
        afterDip = RESERVE.dippedIntoReserve();
        lastAfterDip = afterDip;

        emit ProbeResult(
            "after",
            address(this),
            msg.sender,
            lastAfterBalance,
            afterDip
        );
    }

    function probeReceiveFrom(
        TestnetRefundSink source,
        uint256 amount
    ) external returns (bool beforeDip, bool duringDip, bool afterDip) {
        lastBeforeBalance = address(this).balance;
        beforeDip = RESERVE.dippedIntoReserve();
        lastBeforeDip = beforeDip;

        emit ProbeResult(
            "before",
            address(this),
            msg.sender,
            lastBeforeBalance,
            beforeDip
        );

        source.refund(payable(address(this)), amount);

        lastDuringBalance = address(this).balance;
        duringDip = RESERVE.dippedIntoReserve();
        lastDuringDip = duringDip;

        emit ProbeResult(
            "during",
            address(this),
            msg.sender,
            lastDuringBalance,
            duringDip
        );

        lastAfterBalance = address(this).balance;
        afterDip = RESERVE.dippedIntoReserve();
        lastAfterDip = afterDip;

        emit ProbeResult(
            "after",
            address(this),
            msg.sender,
            lastAfterBalance,
            afterDip
        );
    }
}
