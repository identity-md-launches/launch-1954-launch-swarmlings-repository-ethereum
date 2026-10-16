// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwarmlingsHook} from "../src/SwarmlingsHook.sol";

/// @dev Keeps launch.json and the source in agreement. On Ethereum mainnet the token's reward currency is IMD
/// and the hook only binds a pool that pairs LING with it; a manifest that pairs LING with anything else
/// (native ETH included) would launch a pool where the hook does nothing at all.
contract ManifestTest is Test {
    using stdJson for string;

    address constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;

    function test_launchJsonPairsWithImdAtTheLaunchTier() public view {
        string memory j = vm.readFile(string.concat(vm.projectRoot(), "/launch.json"));
        assertEq(j.readString(".kind"), "univ4_hook");
        assertEq(
            j.readAddress(".pool.pairedCurrency"), IMD, "pairedCurrency must be IMD: see src/Swarmlings.sol"
        );
        assertEq(j.readUint(".pool.fee"), 12500, "the hook binds only the 1.25% tier");
        assertEq(j.readUint(".pool.tickSpacing"), 60);
        assertEq(j.readString(".hook.contract"), "SwarmlingsHook");
        assertEq(j.readString(".token.contract"), "Swarmlings");
        string[] memory args = j.readStringArray(".hook.constructorArgs");
        assertEq(args.length, 2);
        assertEq(args[0], "$poolManager");
        assertEq(args[1], "$token");
        assertEq(j.readStringArray(".hook.permissions").length, 14, "all 14 hook flags");
    }
}
