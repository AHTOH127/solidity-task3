module.exports = async ({ getNamedAccounts, deployments }) => {
	const { deploy } = deployments
	const { deployer } = await getNamedAccounts()

	console.log('=== Deploying MintableNFT ===')
	const nftDeployment = await deploy('MintableNFT', {
		from: deployer,
		args: [
			'MyAuctionNFT', // NFT 名称
			'MYNFT', // NFT 符号
			'ipfs/bafybeihwavz2xbuhpl76ecvzsk2wb6c7umlvdtq7grizdekacq3ybwu5jq' // 元数据基础路径（替换为实际 IPFS 路径）
		],
		log: true,
		waitConfirmations: 1
	})

	console.log(`MintableNFT deployed to: ${nftDeployment.address}`)
}

module.exports.tags = ['nft', 'core']
