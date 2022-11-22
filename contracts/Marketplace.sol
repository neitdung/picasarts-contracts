// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IHubChild.sol";

contract Marketplace is IHubChild, ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    Counters.Counter private _nftsSold;
    Counters.Counter private _nftCount;
    Counters.Counter private _nftExisted;
    uint256 public RATE_FEE;
    mapping(uint256 => NFT) private _idToNFT;
    mapping(uint256 => Auction) private _idToAuction;
    EnumerableSet.AddressSet private _acceptTokens;
    EnumerableMap.AddressToUintMap private _addressFees;
    uint256 private constant DENOMINATOR = 10000;

    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;
    bytes4 public constant ERC2981INTERFACE = type(IERC2981).interfaceId;
    struct NFT {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address seller;
        address owner;
        address ftContract;
        uint256 price;
        bool listed;
        bool auction;
    }

    struct Auction {
        address bidder;
        uint256 highestBid;
        bool limitTime;
        uint256 timeEnd;
    }

    event NFTListed(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address seller,
        address owner,
        address ftContract,
        uint256 price,
        bool auction
    );

    event NFTUnlisted(uint256 itemId);

    event NFTAddAuction(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address bidder,
        uint256 price
    );

    event NFTSold(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address seller,
        address owner,
        uint256 price
    );

    constructor(uint256 fee) {
        RATE_FEE = fee;
    }

    modifier isAcceptToken(address tokenAddr) {
        require(
            tokenAddr == address(0) || _acceptTokens.contains(tokenAddr),
            "Token is not accepted"
        );
        _;
    }

    // List the NFT on the marketplace
    function listNft(
        address nftContract,
        address ftContract,
        uint256 tokenId,
        uint256 price
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        _nftCount.increment();
        _nftExisted.increment();
        uint256 itemId = _nftCount.current();
        _idToNFT[itemId] = NFT(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            true,
            false
        );

        _idToAuction[itemId] = Auction(address(0), price, false, 0);

        emit NFTListed(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            false
        );
    }

    // List the NFT on the marketplace
    function listAuctionNft(
        address nftContract,
        address ftContract,
        uint256 tokenId,
        uint256 price,
        bool limitTime,
        uint256 timeHour
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        require(
            ERC165Checker.supportsInterface(nftContract, ERC721INTERFACE),
            "Contract needs to be ERC721"
        );

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        _nftCount.increment();
        _nftExisted.increment();
        uint256 itemId = _nftCount.current();

        _idToNFT[itemId] = NFT(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            true,
            true
        );

        _idToAuction[itemId] = Auction(
            address(0),
            price,
            limitTime,
            limitTime ? block.timestamp.add(timeHour.mul(1 hours)) : 0
        );

        emit NFTListed(
            itemId,
            nftContract,
            tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            true
        );
    }

    // Switch auction to simple listed
    function switchToListed(
        uint256 itemId,
        address ftContract,
        uint256 price
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        NFT storage nft = _idToNFT[itemId];
        require(msg.sender == nft.seller, "Sender must be seller");
        require(nft.auction, "NFT must be auction");
        Auction storage auction = _idToAuction[itemId];
        nft.ftContract = ftContract;
        nft.price = price;
        nft.auction = false;
        if (auction.bidder != address(0)) {
            payable(auction.bidder).transfer(auction.highestBid);
        }
        auction.bidder = address(0);
        auction.highestBid = 0;
        auction.limitTime = false;
        auction.timeEnd = 0;
        emit NFTListed(
            itemId,
            nft.nftContract,
            nft.tokenId,
            msg.sender,
            address(this),
            nft.ftContract,
            price,
            false
        );
    }

    // Resell an NFT purchased from the marketplace
    function switchToAuction(
        uint256 itemId,
        address ftContract,
        uint256 price,
        bool limitTime,
        uint256 timeHour
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        NFT storage nft = _idToNFT[itemId];
        require(msg.sender == nft.seller, "Sender must be seller");
        require(!nft.auction, "NFT must not be auction");
        Auction storage auction = _idToAuction[itemId];
        nft.auction = true;
        nft.ftContract = ftContract;
        auction.highestBid = price;
        auction.limitTime = limitTime;
        auction.timeEnd = limitTime
            ? block.timestamp.add(timeHour.mul(1 hours))
            : 0;

        emit NFTListed(
            itemId,
            nft.nftContract,
            nft.tokenId,
            msg.sender,
            address(this),
            nft.ftContract,
            price,
            false
        );
    }

    // Resell an NFT purchased from the marketplace
    function relistNft(
        uint256 itemId,
        address ftContract,
        uint256 price
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        NFT storage nft = _idToNFT[itemId];
        IERC721(nft.nftContract).transferFrom(
            msg.sender,
            address(this),
            nft.tokenId
        );

        nft.seller = msg.sender;
        nft.owner = address(this);
        nft.listed = true;
        nft.ftContract = ftContract;
        nft.price = price;

        _nftsSold.decrement();
        emit NFTListed(
            itemId,
            nft.nftContract,
            nft.tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            false
        );
    }

    // Reauction an NFT purchased from the marketplace
    function reauctionNft(
        uint256 itemId,
        address ftContract,
        uint256 price,
        bool limitTime,
        uint256 timeHour
    ) public isAcceptToken(ftContract) nonReentrant {
        require(price > 0, "Price must be at least 1 wei");
        NFT storage nft = _idToNFT[itemId];
        IERC721(nft.nftContract).transferFrom(
            msg.sender,
            address(this),
            nft.tokenId
        );

        nft.seller = msg.sender;
        nft.owner = address(this);
        nft.listed = true;
        nft.ftContract = ftContract;
        nft.auction = true;
        _nftsSold.decrement();

        Auction storage auction = _idToAuction[itemId];
        auction.highestBid = price;
        auction.limitTime = limitTime;
        auction.timeEnd = limitTime
            ? block.timestamp.add(timeHour.mul(1 hours))
            : 0;

        emit NFTListed(
            itemId,
            nft.nftContract,
            nft.tokenId,
            msg.sender,
            address(this),
            ftContract,
            price,
            true
        );
    }

    function unlistItem(uint256 itemId) external nonReentrant {
        require(_idToNFT[itemId].seller == msg.sender, "Sender is not lister");
        if (_idToNFT[itemId].auction) {
            Auction storage info = _idToAuction[itemId];
            if (info.highestBid > 0) {
                payable(info.bidder).transfer(info.highestBid);
            }
            delete _idToAuction[itemId];
        }
        IERC721(_idToNFT[itemId].nftContract).transferFrom(
            address(this),
            msg.sender,
            _idToNFT[itemId].tokenId
        );
        delete _idToNFT[itemId];
        _idToNFT[itemId].listed = false;
        _nftExisted.decrement();
        emit NFTUnlisted(itemId);
    }

    // Buy an NFT
    function buyNft(uint256 itemId) public payable nonReentrant {
        NFT storage nft = _idToNFT[itemId];
        if (nft.ftContract == address(0)) {
            require(
                msg.value >= nft.price,
                "Not enough ether to cover asking price"
            );
        }
        require(
            nft.listed && !nft.auction,
            "Nft must be listed and not in the auction"
        );
        address payable buyer = payable(msg.sender);
        uint256 fee = _feeOf(msg.sender, nft.ftContract);
        fee = nft.price.mul(fee).div(DENOMINATOR);
        if (
            ERC165Checker.supportsInterface(nft.nftContract, ERC2981INTERFACE)
        ) {
            (address creator, uint256 royaltyAmount) = IERC2981(nft.nftContract)
                .royaltyInfo(nft.tokenId, nft.price);
            if (creator != nft.seller && royaltyAmount > 0) {
                sendAssets(msg.sender, creator, nft.ftContract, royaltyAmount);
                sendAssets(
                    msg.sender,
                    nft.seller,
                    nft.ftContract,
                    nft.price.sub(royaltyAmount.add(fee))
                );
            } else {
                sendAssets(msg.sender, nft.seller, nft.ftContract, nft.price.sub(fee));
            }
        } else {
            sendAssets(msg.sender, nft.seller, nft.ftContract, nft.price.sub(fee));
        }
        sendAssets(msg.sender, owner(), nft.ftContract, fee);

        IERC721(nft.nftContract).transferFrom(
            address(this),
            buyer,
            nft.tokenId
        );
        // payable(_marketOwner).transfer(LISTING_FEE);
        nft.owner = buyer;
        nft.listed = false;

        _nftsSold.increment();
        emit NFTSold(
            itemId,
            nft.nftContract,
            nft.tokenId,
            nft.seller,
            buyer,
            nft.price
        );
    }

    function addAuctionNft(uint256 itemId, uint256 value)
        public
        payable
        nonReentrant
    {
        NFT storage nft = _idToNFT[itemId];
        require(
            nft.listed && nft.auction,
            "Nft must be listed and not in the auction"
        );
        Auction storage auction = _idToAuction[itemId];

        require(
            msg.sender != auction.bidder && msg.sender != nft.seller,
            "Sender must be not seller or highest bidder"
        );
        require(
            !auction.limitTime || (auction.timeEnd > block.timestamp),
            "Auction has already ended"
        );
        require(
            value > auction.highestBid,
            "Not enough ether to cover highest auction price"
        );

        address bidder = msg.sender;
        if (nft.ftContract != address(0)) {
            IERC20(nft.ftContract).transferFrom(bidder, address(this), value);
        }

        if (auction.bidder != address(0)) {
            sendAssets(
                address(this),
                auction.bidder,
                nft.ftContract,
                auction.highestBid
            );
        }

        auction.bidder = bidder;
        auction.highestBid = value;

        emit NFTAddAuction(itemId, nft.nftContract, nft.tokenId, bidder, value);
    }

    function acceptAuctionNft(uint256 itemId) public payable nonReentrant {
        NFT storage nft = _idToNFT[itemId];
        require(
            nft.listed && nft.auction,
            "Nft must be listed and not in the auction"
        );
        Auction storage auction = _idToAuction[itemId];
        require(msg.sender == nft.seller, "Sender must be seller");
        require(
            !auction.limitTime || (auction.timeEnd < block.timestamp),
            "Auction must be ended or not limit time"
        );
        uint256 fee = _feeOf(msg.sender, nft.ftContract);
        fee = auction.highestBid.mul(fee).div(DENOMINATOR);
        if (
            ERC165Checker.supportsInterface(nft.nftContract, ERC2981INTERFACE)
        ) {
            (address creator, uint256 royaltyAmount) = IERC2981(nft.nftContract)
                .royaltyInfo(nft.tokenId, auction.highestBid);
            if (creator != nft.seller && royaltyAmount > 0) {
                sendAssets(
                    address(this),
                    creator,
                    nft.ftContract,
                    royaltyAmount
                );
                sendAssets(
                    address(this),
                    nft.seller,
                    nft.ftContract,
                    auction.highestBid.sub(royaltyAmount.add(fee))
                );
            } else {
                sendAssets(
                    address(this),
                    nft.seller,
                    nft.ftContract,
                    auction.highestBid.sub(fee)
                );
            }
        } else {
            sendAssets(
                address(this),
                nft.seller,
                nft.ftContract,
                auction.highestBid.sub(fee)
            );
        }
        sendAssets(msg.sender, owner(), nft.ftContract, fee);
        IERC721(nft.nftContract).transferFrom(
            address(this),
            auction.bidder,
            nft.tokenId
        );
        nft.owner = auction.bidder;
        nft.listed = false;
        auction.bidder = address(0);
        auction.highestBid = 0;
        auction.limitTime = false;
        auction.timeEnd = 0;
        emit NFTSold(
            itemId,
            nft.nftContract,
            nft.tokenId,
            nft.seller,
            auction.bidder,
            auction.highestBid
        );
        _nftsSold.increment();
    }

    function getListedNfts() public view returns (NFT[] memory) {
        uint256 nftCount = _nftCount.current();
        uint256 existedItem = _nftExisted.current();
        uint256 unsoldNftsCount = existedItem - _nftsSold.current();

        NFT[] memory nfts = new NFT[](unsoldNftsCount);
        uint256 nftsIndex = 0;
        for (uint256 i = 0; i < nftCount && nftsIndex<= unsoldNftsCount; i++) {
            if (_idToNFT[i].listed) {
                nfts[nftsIndex] = _idToNFT[i];
                nftsIndex++;
            }
        }
        return nfts;
    }

    function getMyListedNfts() public view returns (NFT[] memory) {
        uint256 nftCount = _nftCount.current();
        uint256 myListedNftCount = 0;
        for (uint256 i = 0; i < nftCount; i++) {
            if (_idToNFT[i].seller == msg.sender && _idToNFT[i].listed) {
                myListedNftCount++;
            }
        }

        NFT[] memory nfts = new NFT[](myListedNftCount);
        uint256 nftsIndex = 0;
        for (uint256 i = 0; i < nftCount; i++) {
            if (_idToNFT[i].seller == msg.sender && _idToNFT[i].listed) {
                nfts[nftsIndex] = _idToNFT[i];
                nftsIndex++;
            }
        }
        return nfts;
    }

    /* Returns all of user bids */
    function getUserBids()
        external
        view
        returns (NFT[] memory, Auction[] memory)
    {
        uint256 totalItemCount = _nftCount.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToAuction[i].bidder == msg.sender) {
                itemCount += 1;
            }
        }

        NFT[] memory items = new NFT[](itemCount);
        Auction[] memory info = new Auction[](itemCount);

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToNFT[i].owner == msg.sender) {
                uint256 currentId = i;
                NFT memory currentItem = _idToNFT[currentId];
                Auction memory currentInfo = _idToAuction[currentId];
                items[currentIndex] = currentItem;
                info[currentIndex] = currentInfo;
                currentIndex += 1;
            }
        }
        return (items, info);
    }

    function getListAuction() public view returns (Auction[] memory) {
        uint256 nftCount = _nftCount.current();

        Auction[] memory auctions = new Auction[](nftCount);
        uint256 nftsIndex = 0;
        for (uint256 i = 0; i < nftCount; i++) {
            auctions[nftsIndex] = _idToAuction[i];
            nftsIndex++;
        }
        return auctions;
    }

    function getMarketData(address contractAddress, uint256 tokenId)
        public
        view
        returns (NFT memory, Auction memory)
    {
        NFT memory nft;
        Auction memory auction;
        uint256 nftCount = _nftCount.current();
        for (uint256 i = 0; i < nftCount; i++) {
            if (
                _idToNFT[i].nftContract == contractAddress &&
                _idToNFT[i].tokenId == tokenId
            ) {
                nft = _idToNFT[i];
                auction = _idToAuction[i];
                break;
            }
        }

        return (nft, auction);
    }

    function sendAssets(
        address from,
        address to,
        address ftToken,
        uint256 value
    ) private {
        if (ftToken == address(0)) {
            payable(to).transfer(value);
        } else {
            if (from != address(this)) {
                IERC20(ftToken).transferFrom(from, to, value);
            } else {
                IERC20(ftToken).transfer(to, value);
            }
        }
    }

    //IHubChild implement
    function addAcceptToken(address tokenAddr) external override  onlyOwner {
        _acceptTokens.add(tokenAddr);
    }

    function removeToken(address tokenAddr) external override onlyOwner {
        _acceptTokens.remove(tokenAddr);
    }

    function getRateFee() external override view returns (uint256) {
        return RATE_FEE;
    }

    function addWhitelistAddress(address whitelistAddress, uint256 fee)
        external
        override
        onlyOwner
    {
        _addressFees.set(whitelistAddress, fee);
    }

    function removeWhitelistAddress(address whitelistAddress)
        external
        override
        onlyOwner
    {
        _addressFees.remove(whitelistAddress);
    }

    function setRateFee(uint256 rateFee) external override onlyOwner {
        require(rateFee < DENOMINATOR, "Fee numerator must less than 100%");
        RATE_FEE = rateFee;
    }

    struct FeeVars {
        bool exists;
        uint256 value;
    }

    function _feeOf(address walletAddress, address tokenAddress)
        private
        view
        returns (uint256)
    {
        FeeVars memory vars;
        (vars.exists, vars.value) = _addressFees.tryGet(walletAddress);
        if (vars.exists) {
            return vars.value;
        }
        (vars.exists, vars.value) = _addressFees.tryGet(tokenAddress);
        if (vars.exists) {
            return vars.value;
        }
        return RATE_FEE;
    }

    function feeOf(address walletAddress, address tokenAddress)
        external
        override
        view
        returns (uint256)
    {
        return _feeOf(walletAddress, tokenAddress);
    }

    function getTokenFee(address tokenAddress) external override view returns (uint256) {
        return _addressFees.get(tokenAddress);
    }

    function getAcceptTokens() external override view returns (address[] memory) {
        uint256 length = _acceptTokens.length();
        address[] memory addressList = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            addressList[i] = _acceptTokens.at(i);
        }
        return addressList;
    }
}
