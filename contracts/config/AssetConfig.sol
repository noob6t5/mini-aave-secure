// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract AssetConfig {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    struct Config {
        uint8 decimals;
        uint256 collateralFactor;
        uint256 liqThreshold;
        uint256 liqBonus;
        bool exists;
    }

    mapping(address => Config) private assets;

    event AssetListed(
        address indexed asset, uint8 decimals, uint256 collateralFactor, uint256 liqThreshold, uint256 liqBonus
    );

    event AssetUpdated( //  how some1 can borrow against their asset
        //  liquidation triagger
        // bonus incentive for liquidators.
    address indexed asset, uint8 decimals, uint256 collateralFactor, uint256 liqThreshold, uint256 liqBonus);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    //  Single asset listing or update
    function listOrUpdateAsset(
        address asset,
        uint8 decimals,
        uint256 collateralFactor,
        uint256 liqThreshold,
        uint256 liqBonus
    ) public onlyOwner {
        require(asset != address(0), "Invalid asset");

        if (assets[asset].exists) {
            // update existing asset
            assets[asset].decimals = decimals;
            assets[asset].collateralFactor = collateralFactor;
            assets[asset].liqThreshold = liqThreshold;
            assets[asset].liqBonus = liqBonus;

            emit AssetUpdated(asset, decimals, collateralFactor, liqThreshold, liqBonus);
        } else {
            // new asset
            assets[asset] = Config({
                decimals: decimals,
                collateralFactor: collateralFactor,
                liqThreshold: liqThreshold,
                liqBonus: liqBonus,
                exists: true
            });

            emit AssetListed(asset, decimals, collateralFactor, liqThreshold, liqBonus);
        }
    }

    // Batch listing/updating
    function batchListOrUpdate(
        address[] calldata assetList,
        uint8[] calldata decimalsList,
        uint256[] calldata collateralFactors,
        uint256[] calldata liqThresholds,
        uint256[] calldata liqBonuses
    ) external onlyOwner {
        require(
            assetList.length == decimalsList.length && assetList.length == collateralFactors.length
                && assetList.length == liqThresholds.length && assetList.length == liqBonuses.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < assetList.length; i++) {
            listOrUpdateAsset(assetList[i], decimalsList[i], collateralFactors[i], liqThresholds[i], liqBonuses[i]);
        }
    }

    // Read access
    function getConfig(address asset)
        external
        view
        returns (uint8 decimals, uint256 collateralFactor, uint256 liqThreshold, uint256 liqBonus)
    {
        require(assets[asset].exists, "Asset not listed");
        Config memory cfg = assets[asset];
        return (cfg.decimals, cfg.collateralFactor, cfg.liqThreshold, cfg.liqBonus);
    }
}
