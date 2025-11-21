// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";


/**
 *  @dev 铸造NFT
 */
contract MintableNFT is ERC721,ERC721Enumerable, Ownable, Pausable {

    uint256 private _nextTokenId;

    string public baseURI;

    // 触发 BaseURI 更新事件
    event BaseURIUpdated(string newBaseURI);

    constructor(string memory name, string memory symbol, string memory _baseURI) ERC721(name, symbol) Ownable(msg.sender) {
         baseURI = _baseURI;
        _nextTokenId = 1; // 从 1 开始编号
    }

    /**
     * @dev 铸造NFT
     * @param to 接收者地址
     * @return tokenId NFT ID
     */
    function mint(address to) external onlyOwner returns (uint256) {
        require(!paused(), "NFT: contract paused");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }

    /**
     * @dev 批量铸造NFT
     * @param to 批量接收者地址
     * @param quantity 批量数量
     * @return tokenIds NFT ID 数组
     */
    function batchMint(address to, uint256 quantity) external onlyOwner returns (uint256[] memory) {
        require(!paused(), "NFT: contract paused");
        require(quantity > 0, "NFT: quantity must be greater than 0");
        uint256[] memory tokenIds = new uint256[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            tokenIds[i] = tokenId;
        }
        return tokenIds;
    }

    /**
     * @dev 更新 BaseURI
     * @param newBaseURI 新的 BaseURI
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // 重写 ERC721 元数据方法
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json"));
    }

   /**
     * @dev 重写 ERC721Enumerable 的 _update 方法
     * @param to 接收者地址
     * @param tokenId NFT ID
     * @return address 授权者
     */
    function _update(address to,uint256 tokenId,address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev 重写 ERC721Enumerable 的 _increaseBalance 方法
     * @param account 账户地址
     * @param value 值
     */
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    /**
     * @dev 重写 ERC721Enumerable 的 supportsInterface 方法
     * @param interfaceId 接口ID
     * @return bool 是否支持
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
