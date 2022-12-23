// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./standards/PNFT.sol";
import "./interfaces/INFT.sol";
import "./interfaces/IHub.sol";
import "./interfaces/IHubChild.sol";

contract Hub is IHub, AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ARTIST_ROLE = keccak256("ARTIST_ROLE");
    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;

    Counters.Counter private _itemCount;
    uint256[] public collectionIds;
    EnumerableSet.AddressSet private _hubChild;

    struct Collection {
        uint256 cid;
        address contractAddress;
        string name;
        string symbol;
        string metadata;
        address owner;
    }

    uint256 public CREATE_FEE;

    mapping(uint256 => Collection) private _cidToCollection;
    mapping(address => uint256) private _addressToCid;

    event CollectionCreated(
        uint256 cid,
        address indexed owner,
        address indexed nftAddress,
        string indexed metadata
    );

    modifier onlyCollectionOwner(uint256 cid) {
        require(
            _cidToCollection[cid].owner == msg.sender,
            "Only owner can edit metadata"
        );
        _;
    }

    constructor(uint256 fee) {
        CREATE_FEE = fee;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ARTIST_ROLE, msg.sender);
    }

    function setFee(uint256 newFee) public onlyRole(DEFAULT_ADMIN_ROLE) {
        CREATE_FEE = newFee;
    }

    function getCreateFee() public view returns (uint256) {
        return CREATE_FEE;
    }

    function addHubChild(address childAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _hubChild.add(childAddress);
    }

    function removeHubChild(address childAddress)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _hubChild.remove(childAddress);
    }

    //IHub implement
    function addAcceptToken(address tokenAddr)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 childLength = _hubChild.length();
        for (uint256 i = 0; i <= childLength; i++) {
            IHubChild(_hubChild.at(i)).addAcceptToken(tokenAddr);
        }
    }

    function removeToken(address tokenAddr)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 childLength = _hubChild.length();
        for (uint256 i = 0; i <= childLength; i++) {
            IHubChild(_hubChild.at(i)).removeToken(tokenAddr);
        }
    }

    //IPlatformFee implement
    function addWhitelistAddress(address whitelistAddress, uint256 fee)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 childLength = _hubChild.length();
        for (uint256 i = 0; i <= childLength; i++) {
            IHubChild(_hubChild.at(i)).addWhitelistAddress(
                whitelistAddress,
                fee
            );
        }
    }

    function removeWhitelistAddress(address whitelistAddress)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 childLength = _hubChild.length();
        for (uint256 i = 0; i <= childLength; i++) {
            IHubChild(_hubChild.at(i)).removeWhitelistAddress(whitelistAddress);
        }
    }

    function setRateFee(uint256 rateFee) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 childLength = _hubChild.length();
        for (uint256 i = 0; i <= childLength; i++) {
            IHubChild(_hubChild.at(i)).setRateFee(rateFee);
        }
    }

    function createCollection(
        string calldata name,
        string calldata symbol,
        string calldata metadata
    ) public payable onlyRole(ARTIST_ROLE) nonReentrant {
        require(
            msg.value == CREATE_FEE,
            "Need more fee for create collection (include storage banner, logo,...)"
        );
        uint256 itemId = _itemCount.current();
        _itemCount.increment();
        address newPNFT = address(new PNFT(name, symbol, msg.sender));

        _cidToCollection[itemId] = Collection(
            itemId,
            newPNFT,
            name,
            symbol,
            metadata,
            msg.sender
        );
        _addressToCid[newPNFT] = itemId;
        collectionIds.push(itemId);
        emit CollectionCreated(itemId, msg.sender, newPNFT, metadata);
    }

    function listCollection(address nftAddress, string calldata metadata)
        public
        payable
        onlyRole(ARTIST_ROLE)
        nonReentrant
    {
        require(
            msg.value == CREATE_FEE,
            "Need more fee for create collection (include storage banner, logo,...)"
        );
        require(
            ERC165Checker.supportsInterface(nftAddress, ERC721INTERFACE),
            "Contract needs to be ERC721"
        );
        INFT newPNFT = INFT(nftAddress);

        require(newPNFT.owner() == msg.sender, "Caller must be NFT owner");
        require(_addressToCid[nftAddress] == 0, "Contract is listed");

        uint256 itemId = _itemCount.current();
        if (itemId != 0) {
            require(
                nftAddress == _cidToCollection[0].contractAddress,
                "Contract is listed"
            );
        }

        _itemCount.increment();
        _addressToCid[nftAddress] = itemId;
        _cidToCollection[itemId] = Collection(
            itemId,
            nftAddress,
            newPNFT.name(),
            newPNFT.symbol(),
            metadata,
            msg.sender
        );
        collectionIds.push(itemId);
        emit CollectionCreated(itemId, msg.sender, nftAddress, metadata);
    }

    function editMetaData(uint256 cid, string calldata newHash)
        public
        onlyRole(ARTIST_ROLE)
        onlyCollectionOwner(cid)
        nonReentrant
    {
        _cidToCollection[cid].metadata = newHash;
    }

    function transferCollection(uint256 cid, address newOwner)
        public
        onlyRole(ARTIST_ROLE)
        onlyCollectionOwner(cid)
        nonReentrant
    {
        _cidToCollection[cid].owner = newOwner;
    }

    function totalCollections() external view returns (uint256) {
        return _itemCount.current();
    }

    function getCollectionData(uint256 cid)
        public
        view
        returns (Collection memory)
    {
        return _cidToCollection[cid];
    }

    function getCollectionByAddress(address nftAddress)
        public
        view
        returns (Collection memory)
    {
        return _cidToCollection[_addressToCid[nftAddress]];
    }

    function getCollectionsByOwner(address creator)
        public
        view
        returns (Collection[] memory)
    {
        uint256 cCount = _itemCount.current();
        uint256 myCollectionCount = 0;
        for (uint256 i = 0; i < cCount; i++) {
            if (_cidToCollection[i].owner == creator) {
                myCollectionCount++;
            }
        }

        Collection[] memory collections = new Collection[](myCollectionCount);
        uint256 cIndex = 0;
        for (uint256 i = 0; i < cCount; i++) {
            if (_cidToCollection[i].owner == creator) {
                collections[cIndex] = _cidToCollection[i];
                cIndex++;
            }
        }
        return collections;
    }

    function getCollectionsPaginated(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (Collection[] memory)
    {
        require(
            endIndex >= startIndex,
            "End Index needs to be greater than or equal to start Index"
        );
        if (endIndex > collectionIds.length) {
            endIndex = collectionIds.length;
        }
        uint256 length = endIndex - startIndex + 1;
        Collection[] memory info = new Collection[](length);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            info[i] = _cidToCollection[collectionIds[i]];
        }

        return info;
    }

    function getAllCollections() external view returns (Collection[] memory) {
        Collection[] memory collections = new Collection[](
            collectionIds.length
        );
        for (uint256 i = 0; i < collectionIds.length; i++) {
            collections[i] = _cidToCollection[collectionIds[i]];
        }

        return collections;
    }

    function withdrawFee(address to, address tokenAddress, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        sendAssets(address(this), to, tokenAddress, amount);
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
}
