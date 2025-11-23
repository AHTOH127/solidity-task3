require('@nomicfoundation/hardhat-toolbox')

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
	solidity: {
		version: '0.8.28',
		settings: {
			optimizer: {
				enabled: true,
				runs: 200
			}
		}
	},
	networks: {
		sepolia: {
			url: process.env.SEPOLIA_RPC_URL || '',
			accounts: [process.env.PRIVATE_KEY],
			chainId: 0
		}
	},
	namedAccounts: {
		deployer: {
			default: 0
		}
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY
	}
}
