// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AssetConfig} from "../config/AssetConfig.sol";
import {PriceOracle} from "../config/PriceOracle.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/// @notice Minimal Aave-style lending core:
/// - Collateral deposits/withdrawals
/// - Borrow/Repay
/// - Liquidation with close factor + bonus
/// - Health Factor checks
/// Assumptions:
///   * AssetConfig returns risk params in basis points (BPS = 10_000).
///   * PriceOracle returns prices in 1e18.
///   * Token amounts are in native token decimals; we normalize via AssetConfig.decimals.
/// This version has NO interest accrual yet (principal-only).

contract LendingPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ---------- Constants ----------
    uint256 private constant BPS = 10_000; // 100%
    uint256 private constant WAD = 1e18; // 1.0 scaled

    // ---------- Admin / Dependencies ----------
    address public owner;
    AssetConfig public assetConfig;
    PriceOracle public priceOracle;

    // ---------- State / Accounting ----------
    mapping(address => mapping(address => uint256)) public collateralBalances;
    mapping(address => mapping(address => uint256)) public borrowBalances;
    address[] public listedAssets;
    mapping(address => bool) public isListed;
    uint256 public closeFactorBps = 5_000; // 50%

    // ---------- Events ----------
    event OwnerUpdated(address indexed newOwner);
    event AssetListed(address indexed asset);
    event CloseFactorUpdated(uint256 newCloseFactorBps);

    event Deposit(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);
    event Borrow(address indexed user, address indexed asset, uint256 amount);
    event Repay(address indexed user, address indexed asset, uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed user,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint256 seizedAmount
    );

    // ---------- Modifiers ----------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ---------- Init ----------
    constructor(address _assetConfig, address _priceOracle) {
        require(_assetConfig != address(0) && _priceOracle != address(0), "bad deps");
        owner = msg.sender;
        assetConfig = AssetConfig(_assetConfig);
        priceOracle = PriceOracle(_priceOracle);
    }

    // ---------- Admin ----------
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @notice List an ERC20 so the pool will accept it and include it in HF math.
    /// The asset must also be configured in AssetConfig (or reads will revert later).
    function listAsset(address asset) external onlyOwner {
        require(asset != address(0), "zero");
        require(!isListed[asset], "already");
        isListed[asset] = true;
        listedAssets.push(asset);
        emit AssetListed(asset);
    }

    function setCloseFactorBps(uint256 newBps) external onlyOwner {
        require(newBps <= BPS, "gt 100%");
        closeFactorBps = newBps;
        emit CloseFactorUpdated(newBps);
    }

    // ---------- Core: Deposit / Withdraw ----------
    /// @notice Supply collateral.
    // ---------- Core: Deposit / Withdraw ----------
    /// @notice Supply collateral.
    function deposit(address asset, uint256 amount) external nonReentrant {
        require(isListed[asset], "asset not listed");
        require(amount > 0, "amount=0");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        collateralBalances[msg.sender][asset] += amount;
        emit Deposit(msg.sender, asset, amount);
    }

    // ---------- Helpers to fix stack too deep ----------
    // @notice  VSCode didn't notified about deep stack but remix did
    function _getCollateralValue(address user, address asset)
        internal
        view
        returns (uint256 eligible, uint256 liqAdj)
    {
        (uint8 dec, uint256 cfBps, uint256 liqBps,) = assetConfig.getConfig(asset);
        uint256 price = priceOracle.getPrice(asset);
        uint256 cAmt = collateralBalances[user][asset];
        if (cAmt == 0) return (0, 0);
        uint256 cVal = (cAmt * price) / (10 ** dec);
        return ((cVal * cfBps) / BPS, (cVal * liqBps) / BPS);
    }

    function _getDebtValue(address user, address asset) internal view returns (uint256) {
        (uint8 dec,,,) = assetConfig.getConfig(asset);
        uint256 price = priceOracle.getPrice(asset);
        uint256 bAmt = borrowBalances[user][asset];
        if (bAmt == 0) return 0;
        return (bAmt * price) / (10 ** dec);
    }

    // ---------- Core: getAccountData ----------
    function getAccountData(address user)
        public
        view
        returns (uint256 totalEligibleCollateralValueWad, uint256 totalDebtValueWad, uint256 healthFactorWad)
    {
        uint256 eligibleCol = 0;
        uint256 liqAdjCol = 0;
        uint256 debtVal = 0;

        for (uint256 i = 0; i < listedAssets.length; i++) {
            address asset = listedAssets[i];

            (uint256 e, uint256 l) = _getCollateralValue(user, asset);
            eligibleCol += e;
            liqAdjCol += l;
            debtVal += _getDebtValue(user, asset);
        }

        uint256 hf = debtVal == 0 ? type(uint256).max : (liqAdjCol * WAD) / debtVal;
        return (eligibleCol, debtVal, hf);
    }

    /// @notice Withdraw collateral if post-withdraw HF >= 1.0.
    function withdraw(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        uint256 bal = collateralBalances[msg.sender][asset];
        require(bal >= amount, "insufficient collateral");

        // Simulate removal then check HF; if it fails, whole tx reverts & state rolls back.
        collateralBalances[msg.sender][asset] = bal - amount;

        (,, uint256 hf) = getAccountData(msg.sender);
        require(hf >= WAD, "HF<1");

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount);
    }

    // ---------- Core: Borrow / Repay ----------
    /// @notice Borrow an asset if HF remains >=1 and LTV cap is respected; pool must have liquidity.
    function borrow(address asset, uint256 amount) external nonReentrant {
        require(isListed[asset], "asset not listed");
        require(amount > 0, "amount=0");

        // pool liquidity
        uint256 poolBal = IERC20(asset).balanceOf(address(this));
        require(poolBal >= amount, "insufficient liquidity");
        borrowBalances[msg.sender][asset] += amount;

        (uint256 eligibleCol, uint256 debtVal, uint256 hf) = getAccountData(msg.sender);
        require(hf >= WAD, "HF<1");
        require(debtVal <= eligibleCol, "over LTV");

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, asset, amount);
    }

    /// @notice Repay your debt (partial or full).
    function repay(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        uint256 owed = borrowBalances[msg.sender][asset];
        require(owed > 0, "no debt");

        uint256 pay = amount > owed ? owed : amount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), pay);
        borrowBalances[msg.sender][asset] = owed - pay;
        emit Repay(msg.sender, asset, pay);
    }
    // ---------- Core: Liquidation ----------,
}
