// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {Mip4Account} from "../src/Mip4Account.sol";

/// Deploys the Mip4Account implementation through the deterministic CREATE2
/// deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C, present on Monad),
/// so the implementation address is reproducible across testnet and mainnet.
///
///   forge script script/DeployMip4Account.s.sol \
///     --rpc-url $MONAD_TESTNET_RPC --private-key $FUNDER_KEY --broadcast
contract DeployMip4Account is Script {
    bytes32 constant SALT = keccak256("mip4-sca.Mip4Account.v1");

    function run() external {
        vm.startBroadcast();
        Mip4Account impl = new Mip4Account{salt: SALT}();
        vm.stopBroadcast();

        console2.log("Mip4Account implementation:", address(impl));
        console2.log("entryPoint():", address(impl.entryPoint()));
    }
}
