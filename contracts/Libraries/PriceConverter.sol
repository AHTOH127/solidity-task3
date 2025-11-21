// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev 价格转换
 */
library PriceConverter {
  // 价格转换的精度
  uint8 public constant PRICE_FEED_DECIMALS = 8;

  // 目标币种的精度
  uint8 public constant TARGET_DECIMALS = 18;

  // ETH 地址
  address public constant ETH_ADDRESS = address(0);

  // 价格有效期（1h）
  uint256 public constant PRICE_FRESHNESS_THRESHOLD = 3600;


  /**
   * @dev 获取资产价格（USD）
   * @param asset 资产地址
   * @param priceFeeds 价格Feed
   * @param erc20Decimals ERC20精度
   * @return USD价格
   */
  function getAssetUSDPrice(address asset, mapping (address => address) storage priceFeeds, mapping (address => uint8) storage erc20Decimals) internal view returns (uint256) {
    address feedAddress = priceFeeds[asset];
    require(feedAddress != address(0), "PriceConverter: price feed not found");
    AggregatorV3Interface feed = AggregatorV3Interface(feedAddress);
    // 获取价格
    (uint80 roundId, int256 price, uint256 updatedAt, , uint80 answeredInRound ) = feed.latestRoundData();

    require(price > 0, "PriceConverter: price feed is not valid");
    require(answeredInRound >= roundId, "PriceConverter: price feed is stale");
    require(block.timestamp <= updatedAt + PRICE_FRESHNESS_THRESHOLD, "PriceConverter: price feed is expired");

    // 转换小数位：8 → 18
    uint256 priceUsd = uint256(price) * 10 **(TARGET_DECIMALS - PRICE_FEED_DECIMALS);

    // ERC20 额外处理：统一为 18 位资产单位
    if (asset != ETH_ADDRESS) {
        uint8 decimals = erc20Decimals[asset];
        require(decimals > 0 && decimals <= 18, "PriceConverter: invalid decimals");
        if (decimals != TARGET_DECIMALS) {
            priceUsd = priceUsd * 10 **(TARGET_DECIMALS - decimals);
        }
    }
    return priceUsd;
  }


  /**
   * @dev 价格转换（USD）
   * @param asset 资产地址
   * @param amount 数量
   * @param priceFeeds 价格Feed
   * @param erc20Decimals ERC20精度
   * @return USD价格
   */
  function convertTOUSD(address asset, uint256 amount, mapping (address => address) storage priceFeeds, mapping (address => uint8) storage erc20Decimals) internal view returns (uint256) {
    require(amount > 0, "PriceConverter: amount must be greater than 0");
    return getAssetUSDPrice(asset, priceFeeds, erc20Decimals) * amount / 10 ** erc20Decimals[asset];
  }
}