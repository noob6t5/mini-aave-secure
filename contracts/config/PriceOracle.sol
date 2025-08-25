// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract PriceOracle {
    address public owner;

    mapping(address => address) public feeds;

    mapping(address => uint256) private manualPrices;

    event PriceUpdated(address indexed asset, uint256 oldPrice, uint256 newPrice);
    event FeedAdded(address indexed asset, address feed);

    // Modifier for owner-only access
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // Attach a Chainlink feed to an asset
    function addFeed(address asset, address feed) external onlyOwner {
        require(asset != address(0) && feed != address(0), "Invalid addresses");
        feeds[asset] = feed;
        emit FeedAdded(asset, feed);
    }

    // Set manual fallback price for rare assets
    function setManualPrice(address asset, uint256 newPrice) external onlyOwner {
        require(asset != address(0), "Invalid asset");
        require(newPrice > 0, "Invalid price");

        uint256 oldPrice = manualPrices[asset];
        manualPrices[asset] = newPrice;

        emit PriceUpdated(asset, oldPrice, newPrice);
    }

    // Get current price of an asset
    function getPrice(address asset) external view returns (uint256) {
        address feed = feeds[asset];

        if (feed != address(0)) {
            (, int256 answer,,,) = AggregatorV3Interface(feed).latestRoundData();
            require(answer > 0, "Feed returned invalid price");
            return uint256(answer) * 1e10; // normalize 8 decimals -> 1e18
        }

        uint256 manual = manualPrices[asset];
        require(manual > 0, "Price not available");
        return manual;
    }
}
