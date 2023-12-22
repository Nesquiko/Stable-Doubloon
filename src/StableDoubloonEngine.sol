// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {StableDoubloon} from "./StableDoubloon.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title SDEngine
 * @author Nesquiko
 *
 * StableDoubloonEngine manages the stable coin StableDoubloon, which has tokens
 * pegged to $1. The StableDoubloon system has exogenous collateral (wETH and
 * wBTC) and its stability is maintained algorithmically.
 *
 * The SD system should always be "overcollateralized". At no point should the
 * value of all collateral be less then or equal to the dollar backed value of
 * all SD.
 *
 * @notice StableDoubloonEngine is the core of StableDoubloon stable coind system,
 * 	it handles all the logic for minting and redeeming SD, as well as depositing
 *	and withdrawing collateral.
 * @notice Loosely based on the stable coin DAI.
 */
contract StableDoubloonEngine is ReentrancyGuard {
    error StableDoubloonEngine__InvalidConstructorArgs();
    error StableDoubloonEngine__TokenNotAllowed();
    error StableDoubloonEngine__NonZeroAmountRequired();
    error StableDoubloonEngine__TransferFailed();
    error StableDoubloonEngine__BreaksHealthFactor(uint256 healthFactor);
    error StableDoubloonEngine__MintFailed();
    error StableDoubloonEngine__HealthFactorAboveThreshold();
    error StableDoubloonEngine__HealthFactorNotImproved();

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    StableDoubloon private immutable sd;
    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposits;
    mapping(address user => uint256 sdMinted) private sdMinted;
    address[] private collateralTokens;

    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed collateral, uint256 amount);

    modifier nonZero(uint256 amount) {
        if (amount == 0) {
            revert StableDoubloonEngine__NonZeroAmountRequired();
        }
        _;
    }

    modifier isAllowedAsCollateral(address token) {
        if (priceFeeds[token] == address(0)) {
            revert StableDoubloonEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(address sdAddress, address[] memory collateralAddresses, address[] memory priceFeedAddresses) {
        if (collateralAddresses.length != priceFeedAddresses.length) {
            revert StableDoubloonEngine__InvalidConstructorArgs();
        }

        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            priceFeeds[collateralAddresses[i]] = priceFeedAddresses[i];
        }
        collateralTokens = collateralAddresses;
        sd = StableDoubloon(sdAddress);
    }

    /*
     * @param collateral address of the token to deposit as collateral
     * @param amountCollateral the amount to deposit
     * @param amountSd the amount of SD to mint
     * @notice this function will deposit collateral and mint SD in one transaction
     */
    function depositCollateralAndMint(address collateral, uint256 amountCollateral, uint256 amountSd) external {
        depositCollateral(collateral, amountCollateral);
        mint(amountSd);
    }

    /**
     * @param collateral address of the token to deposit as collateral
     * @param amount the amount to deposit
     */
    function depositCollateral(address collateral, uint256 amount)
        public
        isAllowedAsCollateral(collateral)
        nonZero(amount)
        nonReentrant
    {
        collateralDeposits[msg.sender][collateral] += amount;
        emit CollateralDeposited(msg.sender, collateral, amount);

        bool success = IERC20(collateral).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert StableDoubloonEngine__TransferFailed();
        }
    }

    /*
     * @param collateral address of the token to redeem
     * @param amount the amount to redeem
     * @param amountSd the amount of SD to burn
     * @notice this function will redeem collateral and burn SD in one transaction
     */
    function redeemCollateralAndBurn(address collateral, uint256 amount, uint256 amountSd) external {
        burn(amountSd);
        redeemCollateral(collateral, amount);
    }

    /*
     * @notice health factor must be above 1 after redeeming collateral
     */
    function redeemCollateral(address collateral, uint256 amount) public nonZero(amount) nonReentrant {
        _redeemCollateral(collateral, amount, msg.sender, msg.sender);
        revertOnBadHealthFactor(msg.sender);
    }

    /**
     * @param amount the amount of SD to mint
     * @notice requester must have more collateral value than the minimum threshold
     */
    function mint(uint256 amount) public nonZero(amount) nonReentrant {
        sdMinted[msg.sender] += amount;
        revertOnBadHealthFactor(msg.sender);

        bool success = sd.mint(msg.sender, amount);
        if (!success) {
            revert StableDoubloonEngine__MintFailed();
        }
    }

    function burn(uint256 amount) public nonZero(amount) {
        _burn(amount, msg.sender, msg.sender);
    }

    /*
     * @param collateral address of the token to liquidate from the user
     * @param user address of user with health factor below MIN_HEALTH_FACTOR, who will be liquidated
     * @param debtToCover the amount of SD to burn
     * @notice you can partially liquidate a user by passing in a lower debtToCover
     * @notice you will get a liquidation bonus for liquidating a user
     * @notice assumtion, the protocol is 200% overcollateralized
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        nonZero(debtToCover)
        nonReentrant
    {
        uint256 hf = healthFactor(user);
        if (hf >= MIN_HEALTH_FACTOR) {
            revert StableDoubloonEngine__HealthFactorAboveThreshold();
        }

        uint256 collateralFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonus = (collateralFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 toRedeem = collateralFromDebtCovered + bonus;
        _redeemCollateral(collateral, toRedeem, msg.sender, user);
        _burn(debtToCover, user, msg.sender);
        if (healthFactor(user) <= hf) {
            revert StableDoubloonEngine__HealthFactorNotImproved();
        }
        revertOnBadHealthFactor(msg.sender);
    }

    function getAccountCollateralValueUSD(address user) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposits[user][token];
            totalCollateralValue += getUsdValue(token, amount);
        }
        return totalCollateralValue;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function revertOnBadHealthFactor(address user) internal view {
        uint256 hf = healthFactor(user);
        if (hf < MIN_HEALTH_FACTOR) {
            revert StableDoubloonEngine__BreaksHealthFactor(hf);
        }
    }

    /// Returns how close to liquidation a user is.
    function healthFactor(address user) internal view returns (uint256) {
        (uint256 totalSDMinted, uint256 collateralValueUSD) = _getAccountInfo(user);
        uint256 collateralAdjusted = (collateralValueUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjusted * PRECISION) / totalSDMinted;
    }

    function getAccountInfo(address user) external view returns (uint256 totalSDMinted, uint256 collateralValueUSD) {
        return _getAccountInfo(user);
    }

    function _getAccountInfo(address user) internal view returns (uint256 totalSDMinted, uint256 collateralValueUSD) {
        totalSDMinted = sdMinted[user];
        collateralValueUSD = getAccountCollateralValueUSD(user);
        return (totalSDMinted, collateralValueUSD);
    }

    function getTokenAmountFromUsd(address token, uint256 amountUsdInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (amountUsdInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function _redeemCollateral(address collateral, uint256 amount, address to, address from) private {
        // if the user has less collateral than the amount they want to redeem,
        // solidity will revert
        collateralDeposits[from][collateral] -= amount;
        emit CollateralRedeemed(from, to, collateral, amount);

        bool success = IERC20(collateral).transfer(to, amount);
        if (!success) {
            revert StableDoubloonEngine__TransferFailed();
        }
    }

    function _burn(uint256 amount, address onBehalfOf, address from) private {
        sdMinted[onBehalfOf] -= amount;
        bool success = sd.transferFrom(from, address(this), amount);
        if (!success) {
            revert StableDoubloonEngine__TransferFailed();
        }
        sd.burn(amount);
    }
}
