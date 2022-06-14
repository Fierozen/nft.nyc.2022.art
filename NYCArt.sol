// SPDX-License-Identifier: MIT

pragma solidity >=0.8.14;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
How to store metadata+images on IPFS:
 1. Get all metadata and images for all tokens
 2. Deploy/pin to IPFS as one folder
 3. Owner does setBaseURI() to point to the IPFS folder
 4. Repeat if adding more metadata+images

BoredApe did this:
 - Query a tokenID here to see, their mint DOES NOT take any uri: https://etherscan.io/token/0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d#readContract
 - Here is the tokenURI for BoredApe ID #11: https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/11
 - Here is the image link below it: https://ipfs.io/ipfs/QmVvdAbabZ2awja88uUhYHFuq67iEiroFuwLGM6HyiWcc8

If you want artists to add images themselves, redesign the mint function
*/

contract NYCArt is ERC721Enumerable, Ownable, ReentrancyGuard {
    // Sale royalty (in percentage points)
    uint256 public constant SALE_ROYALTY_ARTIST = 75;
    uint256 public constant SALE_ROYALTY_NFTNYC = 25;

    // Resale royalty in this marketplace (in percentage points, total is 10% of resale)
    uint256 public constant RESALE_ROYALTY_ARTIST = 7;
    uint256 public constant RESALE_ROYALTY_NFTNYC = 3;
    uint256 public constant RESALE_SELLER_PROCEEDS = 90;

    /// @notice A price for each token is set by the manager.
    mapping (uint256 => uint256) public mintingPrices;

    /// @notice The royalty address for each token is set by the manager.
    mapping (uint256 => address payable) public royaltyAddresses;

    /// @notice A resale price for each token may be set by the owner.
    mapping (uint256 => uint256) public resalePrices;

    /// @notice An owner can list on the marketplace for a price.
    mapping (uint256 => address payable) public resaleSellers;

    string internal _baseURIStorage;

    // Admin functions /////////////////////////////////////////////////////////

    constructor(string memory baseURI) ERC721("NFTNYC Art Project", "NYCART") {
        _baseURIStorage = baseURI;
    }

    function withdrawAll() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseURIStorage = baseURI;
    }

    /// @notice Set minting prices for tokens
    function setMintPrices(uint256[] calldata tokenIds, uint256[] calldata tokenMintPrices) external onlyOwner {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint256 mintPrice = tokenMintPrices[i];
            mintingPrices[tokenId] = mintPrice;
        }
    }

    /// @notice Set royalty addresses for tokens
    function setRoyaltiesAddresses(uint256[] calldata tokenIds, address payable[] calldata tokenRoyaltyAddresses) external onlyOwner {
        for (uint i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            address payable royaltyAddress = tokenRoyaltyAddresses[i];
            royaltyAddresses[tokenId] = royaltyAddress;
        }
    }

    // Minting /////////////////////////////////////////////////////////////////

    /// @notice Main function for the NFT primary sale
    /// Prerequisites
    /// - NFT put to sale with designated mint price, set by "setMintingPrices"
    /// - NFT has a designated royalty recipient, set by "setRoyaltiesRecipients"
    function mint(uint256 tokenId) external payable nonReentrant {
        require(mintingPrices[tokenId] > 0, "Token not for sale");
        require(royaltyAddresses[tokenId] != address(0), "Token not for sale");
        require(msg.value >= mintingPrices[tokenId], "Ether value sent is below the price");
        _safeMint(msg.sender, tokenId);

        // Pay royalty
        uint256 royalty = mintingPrices[tokenId] * SALE_ROYALTY_ARTIST / 100;
        royaltyAddresses[tokenId].transfer(royalty);
    }

    // Marketplace /////////////////////////////////////////////////////////////

    /// @notice Owner can set a price for a token
    function allowBuy(uint256 tokenId, uint256 price) external {
        require(msg.sender == ownerOf(tokenId), "Not owner of this token");
        require(price > 0, "Set a price greater than 0");
        resalePrices[tokenId] = price;
        resaleSellers[tokenId] = payable(msg.sender);
    }

    /// @notice Disallow to trade by the owner
    function disallowBuy(uint256 tokenId) external {
        require(msg.sender == ownerOf(tokenId), "Not owner of this token");
        delete resalePrices[tokenId];
        delete resaleSellers[tokenId];
    }

    /// @notice Buy a token listed on the marketplace
    /// Prerequisites
    /// - NFT was previously minted on primary sale, using "mint"
    /// - NFT is listed for resale as the current owner with desired price, using "allowBuy" 
    function buy(uint256 tokenId) external payable {
        uint256 price = resalePrices[tokenId];
        address payable seller = resaleSellers[tokenId];
        require(price > 0, "This token is not for sale");
        require(ownerOf(tokenId) == seller, "This token is not for sale");
        require(msg.value == price, "Ether value sent is not equal to the price");
        
        // Pay proceeds to seller
        uint256 proceeds = price * RESALE_SELLER_PROCEEDS / 100;
        seller.transfer(proceeds);

        // Pay royalty to artist
        uint256 royalty = price * RESALE_ROYALTY_ARTIST / 100;
        royaltyAddresses[tokenId].transfer(royalty);

        // The royalty to NFTNYC is left in this contract, to collect with withdrawAll()

        _transfer(seller, msg.sender, tokenId);
        delete resalePrices[tokenId];
        delete resaleSellers[tokenId];
    }

    // Plumbing ////////////////////////////////////////////////////////////////

    /// @notice All tokens for an owner
    function tokensOfOwner(address owner_) external view returns(uint256[] memory) {
        uint256 tokenCount = balanceOf(owner_);
        uint256[] memory result = new uint256[](tokenCount);
        for (uint256 index = 0; index < tokenCount; index++) {
            result[index] = tokenOfOwnerByIndex(owner_, index);
        }
        return result;
    }

    function _baseURI() internal override view returns (string memory) {
        return _baseURIStorage;
    }
}