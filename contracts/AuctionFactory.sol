// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./Auction.sol";
import "./Libraries/PriceConverter.sol";

/**
 * @dev 拍卖工厂
 */
contract AuctionFactory is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  // 拍卖合约地址(UUPS)
  address public auctionImpl;
  // 所有拍卖合约地址
  address[] public allAuctions;
  // nft -> 拍卖合约映射
  mapping (address => mapping(uint256 => address)) public nftToAuctions;
  // 资产 -> 价格Feed映射
  mapping (address => address) public priceFeeds;
  // ERC20精度映射
  mapping (address => uint8) public erc20Decimals;


  event AuctionDeployed(address indexed auction, address indexed nft, uint256 indexed tokenId, address seller);

  event PriceFeedRegistered(address indexed assset, address indexed feed);

  event ERC20DecimalsRegistered(address indexed erc20, uint8 decimals);

  event AuctionImplUpdated(address indexed newImpl);

  constructor() {
    _disableInitializers();
  }


  /**
   * @dev 初始化工厂合约
   * @param _auctionImpl 拍卖合约实现地址
   * @param _ethPriceFeed ETH价格Feed地址
   */
  function initialize(address _auctionImpl, address _ethPriceFeed) external initializer {
    __Ownable_init(msg.sender);
    __UUPSUpgradeable_init();
    require(_auctionImpl != address(0), "AuctionFactory: invalid auctionImpl");
    require(_ethPriceFeed != address(0), "AuctionFactory: invalid ethPriceFeed");

    auctionImpl = _auctionImpl;

    // 注册ETH价格
    priceFeeds[PriceConverter.ETH_ADDRESS] = _ethPriceFeed;
    // 固定小数位
    erc20Decimals[PriceConverter.ETH_ADDRESS] = 18;
  }


  /**
   * @dev 创建拍卖
   * @param params 拍卖参数
   * @return auction 拍卖合约地址
   */
  function createAuction(Auction.AuctionInitParams calldata params) external returns (address auction) {
    // 验证参数
    require(params.nftContract != address(0), "AuctionFactory: invalid NFT");
    require(nftToAuctions[params.nftContract][params.tokenId] == address(0), "AuctionFactory: NFT already auctioned");
    require(priceFeeds[params.bidAsset] != address(0), "AuctionFactory: invalid asset");

    // NFT 授权验证
    IERC721 nft = IERC721(params.nftContract);
    require(nft.ownerOf(params.tokenId) == msg.sender, "AuctionFactory: not owner");
    require(nft.isApprovedForAll(msg.sender, address(this)) || nft.getApproved(params.tokenId) == address(this), "AuctionFactory: not approved");

    // 创建新的UUPS代理合约
    auction = address(new ERC1967Proxy(auctionImpl, ""));

    // 初始化UUPS代理合约
    Auction(auction).initialize(params);

    // 更新工厂状态
    allAuctions.push(auction);
    nftToAuctions[params.nftContract][params.tokenId] = auction;

    emit AuctionDeployed(auction, params.nftContract, params.tokenId, msg.sender);

  }

  /**
   * @dev 注册资产价格Feed(仅所有者可用)
   * @param asset 资产地址
   * @param feed 价格Feed地址
   */
  function registerPriceFeed(address asset, address feed) external onlyOwner {
    require(asset != address(0), "AuctionFactory: invalid asset");
    require(feed != address(0), "AuctionFactory: invalid feed");
    priceFeeds[asset] = feed;
    emit PriceFeedRegistered(asset, feed);
  }

  /**
   * @dev 注册ERC20精度(仅所有者可用)
   * @param erc20 ERC20地址
   * @param decimals 精度
   */
  function registerERC20Decimals(address erc20, uint8 decimals) external onlyOwner {
    require(erc20 != address(0), "AuctionFactory: invalid erc20");
    require(decimals > 0 && decimals <= 18, "AuctionFactory: invalid decimals");
    erc20Decimals[erc20] = decimals;
    emit ERC20DecimalsRegistered(erc20, decimals);
  }

  /**
   * @dev 升级Auction合约实现(仅所有者可用)
   * @param newImpl 新的Auction合约实现地址
   */
  function upgradeAuctionImpl(address newImpl) external onlyOwner {
    require(newImpl != address(0), "AuctionFactory: invalid newImpl");
    auctionImpl = newImpl;
    emit AuctionImplUpdated(newImpl);
  }

  /**
   * @dev 获取所有拍卖合约地址
   * @param start 开始索引
   * @param limit 结束索引
   * @return auctions 所有拍卖合约地址
   */
  function getAllAuctions(uint256 start, uint256 limit) external view returns (address[] memory auctions) {
    uint256 total = allAuctions.length;
    uint256 end = start + limit;
    if (end > total) {
      end = total;
    }
    auctions = new address[](end - start);
    for (uint256 i = start; i < end; i++) {
      auctions[i - start] = allAuctions[i];
    }
    return auctions;
  }

  /**
   * @dev 升级UUPS代理合约(仅所有者可用)
   * @param newImplementation 新的UUPS代理合约地址
   */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

}