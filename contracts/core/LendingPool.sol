// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import { AssetConfig } from "../config/AssetConfig.sol";
import { PriceOracle } from "../config/PriceOracle.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";   
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";  


contract LendingPollV1 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000; // 100% BPS
    uint256 private constant WAD = 1e18;

    // admin's 
    address public owner;
    AssetConfig public assetConfig;
    PriceOracle public priceOracle;
    // owner: The god-mode address. Can list assets, change parameters.
    // assetConfig: External contract for all asset risk configs (keeps pool lean and modular).
    // priceOracle: External contract for price feeds (no on-chain price magic here).

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

    event OwnerUpdated(address indexed newOner);
    event AssestListed(address indexed asset);
    event closeFactorUpdated(uint256 newClosedFactorBps);

    modifier onlyOwner() {
        require(msg.sender == owner , "Not the owner");
        _;
    }

    constructor(address _assetConfig, address _priceOracle){
        require(_assetConfig != address(0) && _priceOracle != address(0), "bad deps");
        owner = msg.sender;
        assetConfig=AssetConfig(_assetConfig);
        priceOracle=PriceOracle(_priceOracle);
    }

    function transferOwnership(address newOwner) external onlyOwner{
        require(newOwner != address(0),"zero");
        owner= newOwner;
        emit OwnerUpdated(newOwner);
    }





    




}


