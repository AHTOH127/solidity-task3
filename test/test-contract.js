const { expect } = require('chai')
const { ethers, deployments } = require('hardhat')

describe('NFT Auction Market Test', function () {
	let nft, factory, auctionImpl

	let deployer, seller, bidder1, bidder2

	let tokenId, auctionAddress

	// 测试参数
	const MIN_BID_USD = ethers.parseEther('10') // 最低$10

	const DURATION = 3600 // 1 小时拍卖

	const ETH_BID_AMOUNT = ethers.parseEther('0.01') // Sepolia ETH 约 20$

	const USDC_BID_AMOUNT = ethers.parseUnits('20', 6) // 20 USDC（6 位小数）

	beforeEach(async function () {
		// 获取测试账户
		;[deployer, seller, bidder1, bidder2] = await ethers.getSigners()

		// 部署新合约
		await deployments.fixture(['NFT', 'AuctionFactory', 'AuctionImpl'])

		// 获取合约实例
		nft = await ethers.getContract('MintableNFT')
		factory = await ethers.getContract('AuctionFactory')
		auctionImpl = await ethers.getContract('Auction')

		// 开始铸造
		await nft.connect(deployer).mint(seller.address)
		tokenId = 1 // NFTId 为1

		// 卖家授权工厂合约
		await nft.connect(seller).approve(factory.address, tokenId)
	})

	/**
	 * 测试: 创建ETH拍卖
	 */
	it('Should create ETH auction', async function () {
		// 创建拍卖
		const auctionParams = {
			nftContract: nft.address,
			tokenId: tokenId,
			bidAsset: ethers.ZeroAddress,
			startTime: 0,
			minBidUSD: MIN_BID_USD,
			duration: DURATION
		}

		const createTx = await factory.connect(seller).createAuction(auctionParams)
		await createTx.wait()
		auctionAddress = await factory.nftToAuction(nft.address, tokenId)
		const auction = await ethers.getContractAt('Auction', auctionAddress)

		// 验证拍卖状态
		let auctionInfo = await auction.getAuctionInfo()
		expect(auctionInfo.status).to.equal(1) // ACTIVE
		expect(auctionInfo.seller).to.equal(seller.address)

		// 出价者出价ETH
		await auction.connect(bidder1).bid({ value: ETH_BID_AMOUNT })
		auctionInfo = await auction.getAuctionInfo()
		expect(auctionInfo.highestBidder).to.equal(bidder1.address)
		expect(auctionInfo.highestBid).to.equal(ETH_BID_AMOUNT)

		// 快进时间到拍卖结束
		await ethers.provider.send('evm_increaseTime', [DURATION + 10])
		await ethers.provider.send('evm_mine')

		// 结算拍卖
		const sellerBalanceBefore = await ethers.provider.getBalance(seller.address)
		await auction.connect(seller).settleAuction()

		// 验证拍卖结果
		expect(await nft.ownerOf(tokenId)).to.equal(bidder1.address)

		// 验证卖家收到的资金
		const sellerBalanceAfter = await ethers.provider.getBalance(seller.address)
		expect(sellerBalanceAfter).to.be.gt(sellerBalanceBefore)
	})

	/**
	 * 测试: 创建USDC拍卖
	 */
	it('Should create USDC auction', async function () {
		const usdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA0291'
		const usdc = await ethers.getContractAt('IERC20', usdcAddress)

		// 出价者1授权拍卖工厂
		await usdc.connect(bidder1).approve(factory.address, USDC_BID_AMOUNT)

		// 创建拍卖
		const auctionParams = {
			nftContract: nft.address,
			tokenId: tokenId,
			bidAsset: usdcAddress,
			startTime: 0,
			minBidUSD: MIN_BID_USD,
			duration: DURATION
		}

		await factory.connect(seller).createAuction(auctionParams)
		auctionAddress = await factory.nftToAuction(nft.address, tokenId)
		const auction = await ethers.getContractAt('Auction', auctionAddress)

		// 验证拍卖
		await auction.connect(bidder1).bid()
		const auctionInfo = await auction.getAuctionInfo()
		expect(auctionInfo.highestBidder).to.equal(USDC_BID_AMOUNT)
	})

	/**
	 * 测试: 合约升级
	 */
	it('Should upgrade auction contract', async function () {
		// 部署新合约
		const newAuction = await ethers.getContractFactory('Auction')
		const newAuctionImpl = await newAuction.deploy()
		await newAuctionImpl.waitForDeployment()

		// 升级工厂拍卖地址
		await factory.connect(deployer).upgradeAuctionImpl(newAuctionImpl.target)
		expect(await factory.auctionImpl()).to.equal(newAuctionImpl.target)

		const auctionParams = {
			nftContract: nft.address,
			tokenId: tokenId,
			bidAsset: ethers.ZeroAddress,
			startTime: 0,
			duration: DURATION,
			minBidUsd: MIN_BID_USD
		}

		await factory.connect(seller).createAuction(auctionParams)
		auctionAddress = await factory.nftToAuction(nft.address, tokenId)
		const auction = await ethers.getContractAt('Auction', auctionAddress)
	})
})
