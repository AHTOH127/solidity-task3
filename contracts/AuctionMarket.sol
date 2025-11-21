// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract AuctionMarket is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Auction {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startTime;
        uint256 endTime;
        uint256 startPrice;
        address paymentToken;
        address highestBidder;
        uint256 highestBid;
        bool ended;
    }

    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    uint256 public auctionCount; // 拍卖数量
    mapping(uint256 => Auction) public auctions; // 拍卖信息
    mapping(address => mapping(uint256 => uint256)) public nftToAuctionId; // NFT映射到拍卖ID
    mapping(address => address) public priceFeeds; // 价格Feed

    uint256 public platformFee; // 平台手续费
    address public feeRecipient; // 手续费接收者

    /**
     * @dev 事件:创建拍卖
     * @param nftContract NFT合约地址
     * @param tokenId NFT ID
     * @param startTime 拍卖开始时间
     * @param endTime 拍卖结束时间
     * @param startPrice 起拍价格
     * @param paymentToken 支付代币
     */
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 startTime, uint256 endTime, uint256 startPrice, address paymentToken);

    /**
     * @dev 事件:新的出价
     * @param auctionId 拍卖ID
     * @param bidder 出价者
     * @param bidAmount 出价金额
     * @param bidAmountInUSD 出价金额(USD)
     */
    event NewBid(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount, uint256 bidAmountInUSD);


    /**
     * @dev 事件:拍卖结束
     * @param auctionId 拍卖ID
     * @param winner 拍卖 winner
     * @param amount 拍卖金额
     */
    event AuctionEnded(uint256 indexed auctionId, address indexed winner, uint256 amount);

    /**
     * @dev 事件:取消拍卖
     * @param auctionId 拍卖ID
     */
    event AuctionCanceled(uint256 indexed auctionId);


    /**
     * @dev 升级函数
     * @param initialOwner 合约创建者
     */
   function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        platformFee = 2; // 默认平台手续费为2%
        feeRecipient = msg.sender; // 默认手续费接收者为合约创建者
   }


   /**
   * @dev 升级授权函数
   * @param newImplementation 新的实现合约地址
   */
   function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  /**
   * @dev 设置价格Feed
   * @param token 代币地址
   * @param priceFeed 价格Feed地址
   */
   function setPriceFeed(address token, address priceFeed) external onlyOwner {
       priceFeeds[token] = priceFeed;
   }

  /**
   * @dev 设置平台手续费
   * @param _feeRecipient 平台手续费
   */
   function setFeeRecipient(address _feeRecipient) external onlyOwner {
       feeRecipient = _feeRecipient;
   }

  /**
   * @dev 创建拍卖
   * @param nftContract NFT合约地址
   * @param tokenId NFT ID
   * @param duration 拍卖持续时间
   * @param startPrice 起拍价格
   * @param paymentToken 支付代币
   */
   function createAction(address nftContract, uint256 tokenId, uint256 duration, uint256 startPrice, address paymentToken) external returns(uint256) {
        require(duration >= MIN_AUCTION_DURATION, "Duration must be at least one hour");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not the owner of the NFT");
        require(nftToAuctionId[nftContract][tokenId] == 0, "NFT is already in an auction");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        auctionCount++;
        uint256 auctionId = auctionCount;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            startPrice: startPrice,
            paymentToken: paymentToken,
            highestBidder: address(0),
            highestBid: 0,
            ended: false
        });

        nftToAuctionId[nftContract][tokenId] = auctionId;

        emit AuctionCreated(auctionId, msg.sender, nftContract, tokenId, block.timestamp, block.timestamp + duration, startPrice, paymentToken);

        return auctionId;
   }


  /**
   * @dev 设置价格
   * @param auctionId 拍卖ID
   * @param amount 出价金额
   */
   function placeBid(uint256 auctionId, uint256 amount) external payable nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp >= auction.startTime, "Auction has not started");
        require(block.timestamp <= auction.endTime, "Auction has ended");
        require(!auction.ended, "Auction has ended");
        require(amount >= auction.startPrice, "Bid must be at least the starting price");
        require(amount > auction.highestBid, "Bid must be higher than the current highest bid");

        // 获取支付代币价格
        if (auction.paymentToken == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount sent");
            if (auction.highestBidder != address(0)) {
                payable(auction.highestBidder).transfer(auction.highestBid);
            }
        } else {
          require(msg.value == 0, "ETH must be sent for ERC20 payments");
          IERC20 token = IERC20(auction.paymentToken);
          require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
          if (auction.highestBidder != address(0)) {
              token.transfer(auction.highestBidder, auction.highestBid);
          }
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = amount;
        // 获取支付代币价格
        uint256 amountInUSD = getAmountInUSD(auction.paymentToken, amount);

        emit NewBid(auctionId, msg.sender, amount, amountInUSD);
   }

  /**
   * @dev 结束拍卖
   * @param auctionId 拍卖ID
   */
   function endAuction(uint256 auctionId) external nonReentrant {
      Auction storage auction = auctions[auctionId];
      require(!auction.ended, "Auction has already ended");
      require(block.timestamp > auction.endTime || msg.sender == auction.seller, "Auction has not ended yet");
      auction.ended = true;
      delete nftToAuctionId[auction.nftContract][auction.tokenId];

      if (auction.highestBidder != address(0)) {
          IERC721(auction.nftContract).transferFrom(address(this), auction.highestBidder, auction.tokenId);
          // 计算平台手续费
          uint256 feeAmount = (auction.highestBid * platformFee) / 10000;
          // 计算销售者金额
          uint256 sellerAmount = auction.highestBid - feeAmount;

          if (auction.paymentToken == address(0)) {
              payable(auction.seller).transfer(sellerAmount);
              payable(feeRecipient).transfer(feeAmount);
          } else {
              IERC20 token = IERC20(auction.paymentToken);
              token.transfer(auction.seller, sellerAmount);
              token.transfer(feeRecipient, feeAmount);
          }

          emit AuctionEnded(auctionId, auction.highestBidder, auction.highestBid);

      } else {

        IERC721(auction.nftContract).transferFrom(address(this), auction.seller, auction.tokenId);

        emit AuctionCanceled(auctionId);
      }
   }


  /**
   * @dev 获取支付代币价格
   * @param token 支付代币
   * @param amount 支付金额
   */
   function getAmountInUSD(address token, uint256 amount) public view returns (uint256) {
    address priceFeed = priceFeeds[token];
    if (priceFeed == address(0)) return 0;
    AggregatorV3Interface priceFeedContract = AggregatorV3Interface(priceFeed);
    (, int256 price, , , ) = priceFeedContract.latestRoundData();
    uint8 decimals = priceFeedContract.decimals();
    return (amount * uint256(price)) / (10 ** decimals);
   }


  /**
   * @dev 获取拍卖信息
   * @param auctionId 拍卖ID
   */
   function getAuction(uint256 auctionId) external view returns (Auction memory) {
      return auctions[auctionId];
   }


  /**
   * @dev 获取拍卖ID
   * @param nftContract NFT合约
   * @param tokenId NFT ID
   */
   function getActionId(address nftContract, uint256 tokenId) external view returns (uint256) {
      return nftToAuctionId[nftContract][tokenId];
   }
}