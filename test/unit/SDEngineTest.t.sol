// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeploySD} from "../../script/DeploySD.s.sol";
import {DeployConfig} from "../../script/DeployConfig.s.sol";
import {StableDoubloonEngine} from "../../src/StableDoubloonEngine.sol";
import {StableDoubloon} from "../../src/StableDoubloon.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract SDEngineTest is Test {
    DeploySD deployer;
    StableDoubloon sd;
    StableDoubloonEngine engine;
    DeployConfig config;
    address wETHUsdPriceFeed;
    address wETH;
    address user;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        user = makeAddr("user");
        deployer = new DeploySD();
        (sd, engine, config) = deployer.run();
        (wETH,, wETHUsdPriceFeed,,) = config.activeConfig();
        ERC20Mock(wETH).mint(address(user), AMOUNT_COLLATERAL);
    }

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18; // ETH price is 2k
        uint256 usdValue = engine.getUsdValue(wETH, ethAmount);
        assertEq(usdValue, expectedUsd);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(StableDoubloonEngine.StableDoubloonEngine__NonZeroAmountRequired.selector);
        engine.depositCollateral(wETH, 0);
        vm.stopPrank();
    }
}
