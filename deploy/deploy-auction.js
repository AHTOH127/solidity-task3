const { ethers } = require('hardhat')

module.exports = async ({ getNamedAccounts, deployments }) => {
	const { deploy } = deployments
	const { deployer } = await getNamedAccounts()

	// 1. 部署拍卖合约实现（UUPS）
	console.log('=== Deploying Auction Implementation ===')
	const auctionImpl = await deploy('Auction', {
		from: deployer,
		args: [],
		log: true,
		waitConfirmations: 1
	})

	// 2. 部署拍卖工厂（UUPS 代理）
	console.log('=== Deploying AuctionFactory ===')
	// Sepolia 测试网 ETH/USD 价格Feed地址（Chainlink 官方）
	const ethPriceFeed = '0x694AA1769357215DE4FAC081bf1f309e6763497'
	const factoryDeployment = await deploy('AuctionFactory', {
		from: deployer,
		args: [auctionImpl.address, ethPriceFeed],
		log: true,
		waitConfirmations: 1,
		proxy: {
			proxyContract: 'OpenZeppelinUpgradesUUPS', // UUPS 代理模式
			execute: {
				init: {
					methodName: 'initialize',
					args: [auctionImpl.address, ethPriceFeed]
				}
			}
		}
	})

	// 3. 注册测试 ERC20 价格Feed（示例：USDC/USD）
	const factory = await ethers.getContractAt('AuctionFactory', factoryDeployment.address)
	const usdcAddress = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA0291' // Sepolia USDC
	const usdcPriceFeed = '0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f' // Sepolia USDC/USD Feed
	await factory.registerPriceFeed(usdcAddress, usdcPriceFeed)
	await factory.registerERC20Decimals(usdcAddress, 6) // USDC 是 6 位小数
	console.log('USDC Price Feed registered')

	console.log(`AuctionFactory deployed to: ${factoryDeployment.address}`)
}

module.exports.tags = ['auction-core', 'core']
module.exports.dependencies = ['nft']
