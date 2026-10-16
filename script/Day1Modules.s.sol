// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SwarmlingsHook} from "../src/SwarmlingsHook.sol";
import {SwarmlingsCouncil} from "../src/SwarmlingsCouncil.sol";
import {ISwarmlingsHook, Callbacks} from "../src/interfaces/IHive.sol";
import {TwapOracle} from "../src/modules/TwapOracle.sol";
import {VolatilityFee} from "../src/modules/VolatilityFee.sol";
import {BuybackBurn} from "../src/modules/BuybackBurn.sol";
import {AutoLiquidity} from "../src/modules/AutoLiquidity.sol";
import {TreasurySink} from "../src/modules/TreasurySink.sol";

/// @notice Day-one configuration of the Hive, run from the council owner (the dev wallet) once the launch is
/// live. Deploys the modules and attaches them through the council in the same broadcast.
///
/// HOOK=0x... [VOL_WINDOW=3600 VOL_BPS_PER_PCT=50 VOL_CAP=375] [BUYBACK_BPS=0 BUYBACK_MIN=5e18]
/// [AUTOLP_BPS=0 AUTOLP_THRESHOLD=50e18] [TREASURY_BPS=0 TREASURY_MIN=5e18]
/// forge script script/Day1Modules.s.sol --rpc-url $RPC_URL --private-key $TREASURY_PRIVATE_KEY --broadcast
///
/// Defaults attach only TwapOracle + VolatilityFee (fee quoter for sells, paid to holders); every slice is off
/// unless its bps is set. Amounts are in the reward currency's units (IMD on mainnet: 5e18 = 5 IMD).
contract Day1Modules is Script {
    function run() external {
        SwarmlingsHook hook = SwarmlingsHook(payable(vm.envAddress("HOOK")));
        require(hook.launchPoolSet(), "launch pool not set");
        SwarmlingsCouncil council = SwarmlingsCouncil(hook.council());
        require(council.owner() == msg.sender, "broadcast from the council owner");

        uint32 window = uint32(vm.envOr("VOL_WINDOW", uint256(3600)));
        uint256 perPct = vm.envOr("VOL_BPS_PER_PCT", uint256(50));
        uint256 cap = vm.envOr("VOL_CAP", uint256(375));
        uint16 buybackBps = uint16(vm.envOr("BUYBACK_BPS", uint256(0)));
        uint16 autoLpBps = uint16(vm.envOr("AUTOLP_BPS", uint256(0)));
        uint16 treasuryBps = uint16(vm.envOr("TREASURY_BPS", uint256(0)));
        require(uint256(buybackBps) + autoLpBps + treasuryBps <= hook.MAX_FEE_BPS() - hook.HOLDER_FEE_BPS(), "slices over the cap");

        vm.startBroadcast();
        TwapOracle oracle = new TwapOracle(hook);
        VolatilityFee vol = new VolatilityFee(hook, oracle, window, perPct, cap);
        ISwarmlingsHook.Module[] memory m = new ISwarmlingsHook.Module[](2);
        m[0] = ISwarmlingsHook.Module(address(oracle), Callbacks.BEFORE_SWAP, false);
        m[1] = ISwarmlingsHook.Module(address(vol), Callbacks.QUOTE, false);
        council.execute(address(hook), abi.encodeCall(ISwarmlingsHook.setModules, (m)), "Day one: TwapOracle (observer) and VolatilityFee (sell surcharge below the 1h average, to holders).");
        console2.log("TwapOracle", address(oracle));
        console2.log("VolatilityFee", address(vol));

        uint256 count = (buybackBps > 0 ? 1 : 0) + (autoLpBps > 0 ? 1 : 0) + (treasuryBps > 0 ? 1 : 0);
        if (count > 0) {
            ISwarmlingsHook.Slice[] memory s = new ISwarmlingsHook.Slice[](count);
            uint256 i;
            if (buybackBps > 0) {
                BuybackBurn b = new BuybackBurn(hook, vm.envOr("BUYBACK_MIN", uint256(5e18)));
                s[i++] = ISwarmlingsHook.Slice(address(b), buybackBps, true);
                console2.log("BuybackBurn", address(b));
            }
            if (autoLpBps > 0) {
                AutoLiquidity a = new AutoLiquidity(hook, vm.envOr("AUTOLP_THRESHOLD", uint256(50e18)));
                s[i++] = ISwarmlingsHook.Slice(address(a), autoLpBps, true);
                console2.log("AutoLiquidity", address(a));
            }
            if (treasuryBps > 0) {
                TreasurySink t = new TreasurySink(hook, council.owner(), vm.envOr("TREASURY_MIN", uint256(5e18)));
                s[i++] = ISwarmlingsHook.Slice(address(t), treasuryBps, false);
                console2.log("TreasurySink", address(t));
            }
            council.execute(address(hook), abi.encodeCall(ISwarmlingsHook.setSlices, (s)), "Day one: fee slices.");
        }
        vm.stopBroadcast();
        console2.log("feeBps now", hook.feeBps());
    }
}
