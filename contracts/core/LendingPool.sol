// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import { AssetConfig } from "../config/AssetConfig.sol";
import { PriceOracle } from "../config/PriceOracle.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";   
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";  


contract LendingPollV1 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint256 private constant WAD = 1e18;

    // admin's 
    address public owner;
    AssetConfig public assetConfig;
    PriceOracle public priceOracle;


    mapping(address => mapping(address => uint256)) public borrowBalances;
    address[] public listedAssets;
    mapping(address => bool) public isListed;

    uint256 public closeFactorBps = 5_000 ; // 50% of BPS
    // event's below  for liquidation mechnaism (deposit,withdraw,borrow,repay,liquidation)
    event Deposit  (address indexed user,address indexed asset,uint256 amount);
    event Withdraw (address indexed user,address indexed asset,uint256 amount);
    event Borrow   (address indexed user,address indexed asset,uint256 amount);
    event Repay    (address indexed user,address indexed asset,uint256 amount);
    event Liquidate(
        address indexed liquidator,
        address indexed user,
        address debtAsset,
        address collateralAsset,
        uint256 repayAmount,
        uint256 seizedAmount);

    event ();
    event ();
    event ();



    




}


