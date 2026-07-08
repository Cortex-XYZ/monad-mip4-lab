// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {UnguardedAccount} from "../src/UnguardedAccount.sol";

/// Deploys the UnguardedAccount control implementation (demo contrast runs)
/// through the deterministic CREATE2 deployer, mirroring DeployMip4Account.
contract DeployUnguardedAccount is Script {
    bytes32 constant SALT = keccak256("mip4-sca.UnguardedAccount.v1");

    function run() external {
        vm.startBroadcast();
        UnguardedAccount impl = new UnguardedAccount{salt: SALT}();
        vm.stopBroadcast();

        console2.log("UnguardedAccount implementation:", address(impl));
        console2.log("entryPoint():", address(impl.entryPoint()));
    }
}
