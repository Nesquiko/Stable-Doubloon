// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {StableDoubloon} from "../src/StableDoubloon.sol";
import {StableDoubloonEngine} from "../src/StableDoubloonEngine.sol";
import {DeployConfig} from "./DeployConfig.s.sol";

contract DeploySD is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (StableDoubloon, StableDoubloonEngine) {
        DeployConfig config = new DeployConfig();

        (address wETHPriceFeed, address wBTCPriceFeed, address wETH, address wBTC, uint256 deployerPK) =
            config.activeConfig();
        tokenAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHPriceFeed, wBTCPriceFeed];

        vm.startBroadcast(deployerPK);
        StableDoubloon sd = new StableDoubloon();
        StableDoubloonEngine engine = new StableDoubloonEngine(
            address(sd),
            tokenAddresses,
            priceFeedAddresses
        );
        sd.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (sd, engine);
    }
}
