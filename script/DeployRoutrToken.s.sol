// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {RoutrToken} from "../src/RoutrToken.sol";

/// @title Deploy script for routr (ROUTR)
/// @notice Reviewable reference deployment. On an IdentityMD launch the factory deploys the token
/// itself from the built bytecode, so this script is for local or manual review only. The token has
/// no constructor arguments: whoever deploys it receives the whole supply.
contract DeployRoutrToken is Script {
    /// @notice Deploys the token. Separated from `run()` so tests can call it without a broadcast.
    function deploy() public returns (RoutrToken token) {
        token = new RoutrToken();
    }

    /// @notice Broadcasts the deployment with the signer `forge script` is given.
    function run() external returns (RoutrToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
