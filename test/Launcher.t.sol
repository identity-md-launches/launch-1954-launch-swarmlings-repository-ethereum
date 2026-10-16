// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {CurrencySettler} from "v4-core/test/utils/CurrencySettler.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Swarmlings} from "../src/Swarmlings.sol";
import {SwarmlingsBase} from "./utils/SwarmlingsBase.sol";

/// @dev What IMD's launch verifier checks: the launch factory deploys the hook, holds the launch position as the
/// PoolManager caller, and collects its fee with zero-liquidity calls. Here the test contract plays the factory:
/// it deployed the hook (so it is `launcher`) and calls the PoolManager directly. Also checks that forge-std
/// `deal` can write LING balances and supply, which the verifier uses.
abstract contract LauncherSuite is SwarmlingsBase, IUnlockCallback {
    using CurrencySettler for Currency;

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager));
        ModifyLiquidityParams memory p = abi.decode(data, (ModifyLiquidityParams));
        (BalanceDelta d,) = manager.modifyLiquidity(launchKey, p, "");
        _settleSide(launchKey.currency0, d.amount0());
        _settleSide(launchKey.currency1, d.amount1());
        return "";
    }

    function _settleSide(Currency c, int128 amount) private {
        if (amount < 0) c.settle(manager, address(this), uint256(uint128(-amount)), false);
        if (amount > 0) c.take(manager, address(this), uint256(uint128(amount)), false);
    }

    function _modifyAsLauncher(ModifyLiquidityParams memory p) internal {
        manager.unlock(abi.encode(p));
    }

    function test_launcherIsTheDeployer() public view {
        assertEq(hook.launcher(), address(this));
    }

    function test_launcherCollectsItsWholeFeeInsideTheJitWindow() public {
        int24 lo = TickMath.minUsableTick(SPACING);
        int24 hi = TickMath.maxUsableTick(SPACING);
        // the "factory" opens its own position in this block, as the launch transaction does
        _dealReward(address(this), 100 * BIG);
        _give(address(this), 100_000_000e18);
        _modifyAsLauncher(ModifyLiquidityParams(lo, hi, 1e18, 0));
        _buyExactIn(alice, BIG); // the position earns fees
        uint256 holdersBefore = hook.totalFees();
        uint256 rewardBefore = _rbal(address(this));
        _modifyAsLauncher(ModifyLiquidityParams(lo, hi, 0, 0)); // zero-liquidity collect, same block
        assertEq(hook.totalFees(), holdersBefore, "nothing skimmed from the factory's collect");
        assertGt(_rbal(address(this)), rewardBefore, "the factory received its fee");
    }

    function test_dealWritesLingBalanceAndSupply() public {
        deal(address(ling), carol, 1e18);
        assertEq(ling.balanceOf(carol), 1e18);
        uint256 supply = ling.totalSupply();
        deal(address(ling), carol, 2e18, true);
        assertEq(ling.balanceOf(carol), 2e18);
        assertEq(ling.totalSupply(), supply + 1e18);
    }
}

contract NativeLauncherTest is LauncherSuite {}

contract ImdFirstLauncherTest is LauncherSuite {
    function pairing() internal pure override returns (Pairing) {
        return Pairing.ImdFirst;
    }
}

contract LingFirstLauncherTest is LauncherSuite {
    function pairing() internal pure override returns (Pairing) {
        return Pairing.LingFirst;
    }
}
