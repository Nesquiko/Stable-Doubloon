// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeploySD} from "../../script/DeploySD.s.sol";
import {DeployConfig} from "../../script/DeployConfig.s.sol";
import {StableDoubloonEngine} from "../../src/StableDoubloonEngine.sol";
import {StableDoubloon} from "../../src/StableDoubloon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.sol";

contract InvariantsTest is StdInvariant, Test {
    DeploySD deployer;
    DeployConfig config;
    StableDoubloon sd;
    StableDoubloonEngine engine;
    address wETH;
    address wBTC;
    Handler handler;

    function setUp() external {
        deployer = new DeploySD();
        (sd, engine, config) = deployer.run();
        (wETH, wBTC,,,) = config.activeConfig();
        handler = new Handler(sd, engine);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = sd.totalSupply();
        uint256 totalWethDeposit = IERC20(wETH).balanceOf(address(sd));
        uint256 totalWbtcDeposit = IERC20(wBTC).balanceOf(address(sd));

        uint256 wETHValue = engine.getUsdValue(wETH, totalWethDeposit);
        uint256 wBTCValue = engine.getUsdValue(wBTC, totalWbtcDeposit);

        assert(wETHValue + wBTCValue >= totalSupply);
    }
}
