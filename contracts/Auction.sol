// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Libraries/PriceConverter.sol";

/**
 * @dev 拍卖合约(UUPS升级)
 */
contract Auction is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  // 价格转换
  using PriceConverter for address;

  // 拍卖状态
  enum AuctionState {
    // 待拍卖
    PENDING,
    // 正在拍卖
    ACTIVE,
    // 结束拍卖
    ENDED,
    // 取消拍卖
    CANCELED
  }

  struct AuctionInfo {
    // NFT合约地址
    address nftContract;
    // NFT ID
    uint256 tokenId;
    // 卖家地址
    address seller;
    // 出价
    address bidAsset;
    // 开始时间
    uint256 startTime;
    // 结束时间
    uint256 endTime;
    // 最高价
    uint256 highestBid;
    // 最高价出价者
    address highestBidder;
    // 最低价
    uint256 minBidUsd;
    // 拍卖状态
    AuctionState state;
    // 出价次数
    uint256 bidCount;
  }

  struct AuctionInitParams {
    address nftContract;
    uint256 tokenId;
    address bidAsset;
    uint256 startTime; // 0 = 立即开始
    uint256 duration;  // 秒数
    uint256 minBidUsd; // 美元，18位小数
  }

  AuctionInfo public auctionInfo;

  // 价格Feed
  mapping (address => address) private _priceFeeds;

  // ERC20精度
  mapping (address => uint8) private _erc20Decimals;

  // 出价者余额
  mapping (address => uint256) private _bidderBalances;

  // 事件：拍卖开始
  event AuctionActivated(AuctionInfo auctionInfo);

  // 事件：出价
  event BidSumbitted(address indexed bidder, uint256 amount, uint256 usdAmount);

  // 事件：拍卖取消
  event AuctionCancelled();

  // 事件:拍卖结束
  event AuctionSettled(address indexed winner, address indexed seller, uint256 amount);

  constructor() {
    _disableInitializers();
  }

  /**
   * @dev 设置价格预言机地址
   * @param asset 资产地址
   * @param feed 预言机地址
   */
  function setPriceFeed(address asset, address feed) public onlyOwner {
      require(asset != address(0), "Auction: invalid asset");
      require(feed != address(0), "Auction: invalid feed");
      _priceFeeds[asset] = feed;
  }

  /**
   * @dev 设置ERC20代币精度
   * @param token ERC20代币地址
   * @param decimals 精度
   */
  function setErc20Decimals(address token, uint8 decimals) public onlyOwner {
      require(token != address(0), "Auction: invalid token");
      require(decimals > 0, "Auction: invalid decimals");
      _erc20Decimals[token] = decimals;
  }

  /**
   * @dev 初始化拍卖
   * @param params 拍卖参数
   */
  function initialize(AuctionInitParams calldata params) external initializer {
    __Ownable_init(msg.sender);
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();

    // 参数校验
    require(params.nftContract != address(0), "Auction: invalid NFT");
    require(params.bidAsset != address(0) || params.bidAsset == PriceConverter.ETH_ADDRESS, "Auction: invalid asset");
    require(params.duration > 0, "Auction: duration zero");
    require(params.minBidUsd > 0, "Auction: min bid zero");

    // 计算开始/结束时间
    uint256 startTime = params.startTime == 0 ? block.timestamp : params.startTime;
    uint256 endTime = startTime + params.duration;

    // 初始化拍卖数据
    auctionInfo = AuctionInfo({
      nftContract: params.nftContract,
      tokenId: params.tokenId,
      seller: msg.sender,
      bidAsset: params.bidAsset,
      startTime: startTime,
      endTime: endTime,
      highestBid: 0,
      highestBidder: address(0),
      minBidUsd: params.minBidUsd,
      state: startTime > block.timestamp ? AuctionState.PENDING : AuctionState.ACTIVE,
      bidCount: 0
    });

    // 转移 NFT 到合约（需卖家授权）
    IERC721(params.nftContract).transferFrom(msg.sender, address(this), params.tokenId);

    if (auctionInfo.state == AuctionState.ACTIVE) {
      // 触发拍卖开始事件
      emit AuctionActivated(auctionInfo);
    }
  }

  /**
   * @dev 出价
   */
  function bid() external payable nonReentrant{
    AuctionInfo storage info = auctionInfo;

    // 状态验证
    require(info.state == AuctionState.ACTIVE, "Auction: not active");
    require(block.timestamp < info.endTime, "Auction: ended");
    require(msg.sender != info.seller, "Auction: seller cannot bid");

    address bidAsset = info.bidAsset;
    uint256 bidAmount;

    // 处理ETH出价
    if (bidAsset == PriceConverter.ETH_ADDRESS) {
      require(msg.value > 0, "Auction: zero bid");
      bidAmount = msg.value;
    } else { // 处理ERC20代币出价
      require(msg.value == 0, "Auction: ERC20 bid must use msg.value = 0");
      bidAmount = IERC20(bidAsset).allowance(msg.sender, address(this));
      require(bidAmount > 0, "Auction: zero bid");
      bool success = IERC20(bidAsset).transferFrom(msg.sender, address(this), bidAmount);
      require(success, "Auction: transferFrom failed");
    }

    // 价格转换
    uint256 bidUsd = bidAsset.convertTOUSD(bidAmount, _priceFeeds, _erc20Decimals);
    require(bidUsd >= info.minBidUsd, "Auction: bid too low");
    require(bidUsd > (info.highestBid == 0 ? 0 : bidAsset.convertTOUSD(info.highestBid, _priceFeeds, _erc20Decimals)), "Auction: bid too low");

    // 退还前最高出价者
    if (info.highestBidder != address(0)) {
      _refund(info.highestBidder, info.highestBid);
    }

    // 更新拍卖状态
    info.highestBid = bidAmount;
    info.highestBidder = msg.sender;
    info.bidCount++;

    emit BidSumbitted(msg.sender, bidAmount, bidUsd);
  }


  /**
   * @dev 结束拍卖
   */
  function settleAuction() external nonReentrant{
    AuctionInfo storage info = auctionInfo;

    require(info.state == AuctionState.ACTIVE, "Auction: not active");
    require(block.timestamp >= info.endTime, "Auction: not ended");

    info.state = AuctionState.ENDED;

    // 有最高出价者：转账
    if (info.highestBidder != address(0)) {
      // 转账NFT给赢家
      IERC721(info.nftContract).transferFrom(address(this), info.highestBidder, info.tokenId);

      // 转账给卖家
      _transferToSeller(info.highestBid);

      emit AuctionSettled(info.highestBidder, info.seller, info.highestBid);
    } else { // 无最高出价者：退回NFT
      // 转移NFT给卖家
      IERC721(info.nftContract).transferFrom(address(this), info.seller, info.tokenId);

        emit AuctionSettled(address(0), info.seller, 0);
    }

  }

  /**
   * @dev 取消拍卖
   */
  function cancelAuction() external nonReentrant{
    AuctionInfo storage info = auctionInfo;

    require(info.state == AuctionState.PENDING || (info.state == AuctionState.ACTIVE && info.bidCount == 0), "Auction: cannot cancel");
    require(msg.sender == info.seller, "Auction: not seller");

    info.state = AuctionState.CANCELED;

    // 退回NFT
    IERC721(info.nftContract).transferFrom(address(this), info.seller, info.tokenId);

    emit AuctionCancelled();
  }

  /**
   * @dev 激活拍卖
   */
  function activiteAuction() external {
    AuctionInfo storage info = auctionInfo;
    require(info.state == AuctionState.PENDING, "Auction: not pending");
    require(block.timestamp >= info.startTime, "Auction: not started");
    info.state = AuctionState.ACTIVE;
    emit AuctionActivated(info);
  }

  /**
   * @dev 内部退款函数
   */
  function _refund(address to, uint256 amount) internal {
    require(to != address(0), "Auction: invalid refund address");
    address bidAsset = auctionInfo.bidAsset;

    if (bidAsset == PriceConverter.ETH_ADDRESS) {
      (bool success, ) = to.call{value: amount}("");
      require(success, "Auction: refund failed");
    } else {
      bool success = IERC20(bidAsset).transfer(to, amount);
      require(success, "Auction: refund failed");
    }
  }


  /**
   * @dev 退回NFT给卖家
   */
  function _transferToSeller(uint256 amount) internal {
    address seller = auctionInfo.seller;
    address bidAsset = auctionInfo.bidAsset;

    require(seller != address(0) && amount > 0, "Auction: invalid seller address");

    if (bidAsset == PriceConverter.ETH_ADDRESS) {
      (bool success, ) = auctionInfo.seller.call{value: amount}("");
      require(success, "Auction: transfer to seller failed");
    } else {
      bool success = IERC20(bidAsset).transfer(auctionInfo.seller, amount);
      require(success, "Auction: transfer to seller failed");
    }
  }

  /**
   * @dev UUPS升级授权
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
