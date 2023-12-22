// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DeployConfig is Script {
    struct NetworkConfig {
        address wETH;
        address wBTC;
        address wETHUsdPriceFeed;
        address wBTCUsdPriceFeed;
        uint256 deployerPK;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2_000e8;
    int256 public constant BTC_USD_PRICE = 30_000e8;
    uint256 public constant ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeConfig = getSepoliaConfig();
        } else {
            activeConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wETHUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerPK: vm.envUint("PRIVATE_KEY")
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeConfig.wBTCUsdPriceFeed != address(0)) {
            return activeConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock wETHMock = new ERC20Mock();
        MockV3Aggregator btcPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock wBTCMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wETH: address(wETHMock),
            wBTC: address(wBTCMock),
            wETHUsdPriceFeed: address(ethPriceFeed),
            wBTCUsdPriceFeed: address(btcPriceFeed),
            deployerPK: ANVIL_KEY
        });
    }
}
