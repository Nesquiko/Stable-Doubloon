// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StableDoubloonEngine} from "../../src/StableDoubloonEngine.sol";
import {StableDoubloon} from "../../src/StableDoubloon.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    StableDoubloon sd;
    StableDoubloonEngine engine;

    ERC20Mock wETH;
    ERC20Mock wBTC;

    address[] public depositors;

    constructor(StableDoubloon _sd, StableDoubloonEngine _engine) {
        sd = _sd;
        engine = _engine;
        wETH = ERC20Mock(engine.getCollateralTokens()[0]);
        wBTC = ERC20Mock(engine.getCollateralTokens()[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _collateralFromSeed(collateralSeed);
        amount = bound(amount, 1, type(uint96).max);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(engine), amount);
        engine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        depositors.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _collateralFromSeed(collateralSeed);
        uint256 maxToRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amount = bound(amount, 0, maxToRedeem);
        vm.assume(amount > 0);
       
        engine.redeemCollateral(address(collateral), amount);
    }

    function mint(uint256 amount, uint256 addressSeed) public {
        vm.assume(depositors.length > 0);

        address sender = depositors[addressSeed % depositors.length];
        (uint256 totalSDMinted, uint256 collateralValueUSD) = engine.getAccountInfo(sender);
        int256 maxSdToMint = (int256(collateralValueUSD) / 2) - int256(totalSDMinted);
        vm.assume(maxSdToMint > 0);
        amount = bound(amount, 0, uint256(maxSdToMint));
        vm.assume(amount > 0);

        vm.startPrank(sender);
        engine.mint(amount);
        vm.stopPrank();
    }

    function _collateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        if (seed % 2 == 0) {
            return wETH;
        }
        return wBTC;

    }
}
