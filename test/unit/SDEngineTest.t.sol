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
    address wETH;
    address wBTC;
    address wETHUsdPriceFeed;
    address wBTCUsdPriceFeed;
    address user;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    modifier depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(wETH).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        user = makeAddr("user");
        deployer = new DeploySD();
        (sd, engine, config) = deployer.run();
        (wETH, wBTC, wETHUsdPriceFeed, wBTCUsdPriceFeed,) = config.activeConfig();
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

    address[] public tokens;
    address[] public priceFeeds;

    function testRevertIfIncorrectConstructionCall() public {
        tokens.push(wETH);
        priceFeeds.push(wETHUsdPriceFeed);
        priceFeeds.push(wBTCUsdPriceFeed);

        vm.expectRevert(StableDoubloonEngine.StableDoubloonEngine__InvalidConstructorArgs.selector);
        new StableDoubloonEngine(address(sd), tokens, priceFeeds);
    }

    function testGetTokemAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;

        uint256 actualValue = engine.getTokenAmountFromUsd(wETH, usdAmount);
        assertEq(actualValue, expectedWeth);
    }

    function testRevertsUnapprovedCollateral() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(StableDoubloonEngine.StableDoubloonEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(randomToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalSDMinted, uint256 collValInUsd) = engine.getAccountInfo(user);

        uint256 expectedTotalSDMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(wETH, collValInUsd);
        assertEq(totalSDMinted, expectedTotalSDMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}
