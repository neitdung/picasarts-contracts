// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Farming is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    uint256 private LISTING_FEE;
    address private _owner;
    Counters.Counter private _farmCount;
    mapping(uint256 => Farm) private _idToFarm;
    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;

    enum FarmStatus {
        NOT_INITIAL,
        CREATED,
        RUNNING,
        CLOSED
    }

    struct Farm {
        uint256 farmId;
        address owner;
        FarmStatus status;
        uint256 total;
        uint256 undistributed;
        uint256 pointBalance;
        uint256 lastRound;
        uint256 endRound;
        address seedId;
        uint256 startAt;
        uint256 rps;
        uint256 sessionInterval;
        address nftContract;
        uint256[] tokenIds;
        uint256[] tokenToPoints;
        uint256[] tokenToFarmerId;
        address[] farmers;
        uint256[] balances;
        uint256[] lastClaimed;
    }

    event FarmCreated(
        uint256 farmId,
        address owner,
        address nftContract,
        address seedId
    );

    event FarmActivated(
        uint256 farmId,
        uint256 amount,
        uint256 startAt
    );

    event DepositNFT(
        uint256 farmId,
        uint256 tokenId,
        address nftContract,
        address farmer
    );

    event WithdrawNFT(
        uint256 farmId,
        uint256 tokenId,
        address nftContract,
        address farmer
    );

    event Claim(
        uint256 farmId,
        uint256 amount,
        address farmer
    );

    event FarmClose(
        uint256 farmId,
        uint256 undistributed
    );

    constructor(uint256 fee) {
        _owner = msg.sender;
        LISTING_FEE = fee;
    }

    modifier onlyFarmOwner(uint256 itemId) {
        require(
            _idToFarm[itemId].owner == msg.sender,
            "Sender is not farm owner"
        );
        _;
    }

    function createFarm(
        address nftContract,
        uint256[] calldata acceptTokens,
        uint256[] calldata tokenPoints,
        address seedId,
        uint256 startAt,
        uint256 rps,
        uint256 sessionInterval
    ) public payable {
        uint256 numsToken = acceptTokens.length;
        require(msg.value == LISTING_FEE, "You must add exact listing fee");
        require(
            numsToken == tokenPoints.length,
            "Map of token points must have same length"
        );

        bool isSet = true;
        for (uint256 i = 0; i < numsToken - 1; i++) {
            for (uint256 j = i + 1; j < numsToken; j++) {
                if (acceptTokens[i] == acceptTokens[j]) {
                    isSet = false;
                    break;
                }
            }
        }
        require(isSet, "Token input must be set array");
        uint256 farmId = _farmCount.current();
        _idToFarm[farmId] = Farm(
            farmId,
            msg.sender,
            FarmStatus.CREATED,
            0,
            0,
            0,
            0,
            0,
            seedId,
            startAt,
            rps,
            sessionInterval,
            nftContract,
            acceptTokens,
            tokenPoints,
            new uint256[](numsToken),
            new address[](0),
            new uint256[](0),
            new uint256[](0)
        );
        _idToFarm[farmId].farmers.push(address(0));
        _idToFarm[farmId].balances.push(0);
        _idToFarm[farmId].lastClaimed.push(0);
        _farmCount.increment();
        emit FarmCreated(farmId, msg.sender, nftContract, seedId);
    }

    function addReward(
        uint256 farmId,
        address seedId,
        uint256 amount
    ) external payable onlyFarmOwner(farmId) nonReentrant {
        require(
            _idToFarm[farmId].status == FarmStatus.CREATED ||
                _idToFarm[farmId].status == FarmStatus.RUNNING,
            "Not time for adding total"
        );
        require(seedId == _idToFarm[farmId].seedId, "Wrong seed");
        Farm storage farm = _idToFarm[farmId];
        uint256 rewardAdd = amount;

        if (seedId == address(0)) {
            rewardAdd = msg.value;
        } else {
            IERC20(seedId).transferFrom(msg.sender, address(this), amount);
        }
        farm.total = rewardAdd.add(farm.total);
        farm.undistributed = rewardAdd.add(farm.undistributed);

        if (block.timestamp > farm.startAt && farm.total != 0) {
            farm.startAt = block.timestamp;
            farm.status = FarmStatus.RUNNING;
            emit FarmActivated(farmId, farm.total, farm.startAt);
        }

        uint256 lastRound = farm.endRound;

        if (farm.pointBalance != 0) {
            farm.endRound = rewardAdd.div(farm.pointBalance.mul(farm.rps)).add(
                lastRound
            );
        } else {
            farm.endRound = rewardAdd.div(farm.rps).add(lastRound);
        }
    }

    function depositNft(
        address nftContract,
        uint256 tokenId,
        uint256 farmId
    ) external payable nonReentrant {
        Farm memory tempFarm = _idToFarm[farmId];
        require(
            tempFarm.status != FarmStatus.CLOSED && tempFarm.total > 0,
            "Farm is not active."
        );

        require(
            tempFarm.endRound.mul(tempFarm.sessionInterval).add(
                tempFarm.startAt
            ) > block.timestamp,
            "The farm is not enough total for new farming"
        );
        bool isAccept = false;
        uint256 tokenIndex = 0;
        for (uint256 i = 0; i < tempFarm.tokenIds.length; i++) {
            if (tempFarm.tokenIds[i] == tokenId) {
                isAccept = true;
                tokenIndex = i;
                break;
            }
        }
        require(isAccept, "Token is not accepted for this farm");
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        Farm storage farm = _idToFarm[farmId];

        uint256 curRound = 0;
        if (block.timestamp > farm.startAt) {
            if (farm.status == FarmStatus.CREATED) {
                farm.status = FarmStatus.RUNNING;
            }
            curRound = block.timestamp.sub(tempFarm.startAt).div(
                tempFarm.sessionInterval
            );
        }
        uint256 farmerIndex = 0;
        bool farmerExist = false;
        for (uint256 i = 0; i < tempFarm.farmers.length; i++) {
            if (tempFarm.farmers[i] == msg.sender) {
                farmerExist = true;
                farmerIndex = i;
                break;
            }
        }

        if (!farmerExist) {
            farm.farmers.push(msg.sender);
            farmerIndex = tempFarm.farmers.length;
            farm.balances.push(tempFarm.tokenToPoints[tokenIndex]);
            farm.lastClaimed.push(curRound);
        } else if (
            tempFarm.balances[farmerIndex] > 0 &&
            curRound > tempFarm.lastClaimed[farmerIndex]
        ) {
            uint256 claimAmount = tempFarm
                .balances[farmerIndex]
                .mul(tempFarm.rps)
                .mul(curRound.sub(tempFarm.lastClaimed[farmerIndex]));
            if (tempFarm.seedId == address(0)) {
                payable(msg.sender).transfer(claimAmount);
            } else {
                IERC20(tempFarm.seedId).transfer(msg.sender, claimAmount);
            }
            farm.balances[farmerIndex] = tempFarm.balances[farmerIndex].add(
                tempFarm.tokenToPoints[tokenIndex]
            );
            emit Claim(farmId, claimAmount, msg.sender);
        }

        farm.tokenToFarmerId[tokenIndex] = farmerIndex;
        farm.lastClaimed[farmerIndex] = curRound;
        farm.pointBalance = tempFarm.pointBalance.add(
            tempFarm.tokenToPoints[tokenIndex]
        );
        if (curRound > tempFarm.lastRound) {
            farm.lastRound = curRound;
            farm.undistributed = tempFarm.undistributed.sub(
                tempFarm.rps.mul(tempFarm.pointBalance).mul(
                    curRound.sub(tempFarm.lastRound)
                )
            );
        }
        farm.endRound = curRound.add(
            farm.undistributed.div(tempFarm.rps).div(farm.pointBalance)
        );
        emit DepositNFT(farmId, tokenId, nftContract, msg.sender);
        require(
            curRound < farm.endRound,
            "Undistributed reward does not cover enough new point balance"
        );
    }

    function withdrawNft(uint256 farmId, uint256 tokenIndex)
        external
        payable
        nonReentrant
    {
        Farm memory tempFarm = _idToFarm[farmId];
        uint256 farmerIndex = tempFarm.tokenToFarmerId[tokenIndex];

        require(
            tempFarm.farmers[farmerIndex] == msg.sender,
            "Token is not accepted for withdraw"
        );

        uint256 curRound = 0;
        if (block.timestamp > tempFarm.startAt) {
            curRound = block.timestamp.sub(tempFarm.startAt).div(
                tempFarm.sessionInterval
            );
        }

        Farm storage farm = _idToFarm[farmId];
        if (curRound > tempFarm.lastClaimed[farmerIndex]) {
            uint256 claimAmount = tempFarm
                .balances[farmerIndex]
                .mul(tempFarm.rps)
                .mul(curRound.sub(tempFarm.lastClaimed[farmerIndex]));
            if (tempFarm.seedId == address(0)) {
                payable(msg.sender).transfer(claimAmount);
            } else {
                IERC20(tempFarm.seedId).transfer(msg.sender, claimAmount);
            }
            emit Claim(farmId, claimAmount, msg.sender);
        }
        IERC721(tempFarm.nftContract).transferFrom(
            address(this),
            tempFarm.farmers[farmerIndex],
            tempFarm.tokenIds[tokenIndex]
        );
        farm.tokenToFarmerId[tokenIndex] = 0;
        farm.lastClaimed[farmerIndex] = curRound;
        farm.balances[farmerIndex] = tempFarm.balances[farmerIndex].sub(
            tempFarm.tokenToPoints[tokenIndex]
        );

        farm.pointBalance = tempFarm.pointBalance.sub(
            tempFarm.tokenToPoints[tokenIndex]
        );
        if (curRound > tempFarm.lastRound) {
            farm.lastRound = curRound;
            farm.undistributed = tempFarm.undistributed.sub(
                tempFarm.rps.mul(tempFarm.pointBalance).mul(
                    curRound.sub(tempFarm.lastRound)
                )
            );
        }
        if (farm.pointBalance > 0) {
            farm.endRound = curRound.add(
                farm.undistributed.div(tempFarm.rps).div(farm.pointBalance)
            );
        }
        emit WithdrawNFT(farmId, tempFarm.tokenIds[tokenIndex], tempFarm.nftContract, msg.sender);
    }

    function claimReward(uint256 farmId) external payable nonReentrant {
        Farm memory tempFarm = _idToFarm[farmId];
        uint256 farmerIndex = 0;
        bool farmerExist = false;
        for (uint256 i = 0; i < tempFarm.farmers.length; i++) {
            if (tempFarm.farmers[i] == msg.sender) {
                farmerExist = true;
                farmerIndex = i;
                break;
            }
        }

        require(
            farmerExist && tempFarm.balances[farmerIndex] > 0,
            "You have not locked any nft yet."
        );

        uint256 curRound = 0;
        if (block.timestamp > tempFarm.startAt) {
            curRound = block.timestamp.sub(tempFarm.startAt).div(
                tempFarm.sessionInterval
            );
        }
        require(
            curRound > tempFarm.lastClaimed[farmerIndex],
            "You have not locked enough time"
        );
        uint256 claimAmount = tempFarm
            .balances[farmerIndex]
            .mul(tempFarm.rps)
            .mul(curRound.sub(tempFarm.lastClaimed[farmerIndex]));
        if (tempFarm.seedId == address(0)) {
            payable(msg.sender).transfer(claimAmount);
        } else {
            IERC20(tempFarm.seedId).transfer(msg.sender, claimAmount);
        }
        emit Claim(farmId, claimAmount, msg.sender);
    }

    function closeFarm(uint256 farmId)
        public
        payable
        onlyFarmOwner(farmId)
        nonReentrant
    {
        Farm memory tempFarm = _idToFarm[farmId];
        require(
            tempFarm.status != FarmStatus.CLOSED,
            "It is not time for close farm"
        );
        require(
            tempFarm.endRound > 0 && tempFarm.pointBalance > 0,
            "Farm must have some farmers to close"
        );

        uint256 paybackAmount = tempFarm.undistributed.sub(
            tempFarm.endRound.sub(tempFarm.lastRound).mul(tempFarm.rps).mul(
                tempFarm.pointBalance
            )
        );
        if (paybackAmount > 0) {
            if (tempFarm.seedId == address(0)) {
                payable(msg.sender).transfer(paybackAmount);
            } else {
                IERC20(tempFarm.seedId).transfer(msg.sender, paybackAmount);
            }
        }
        _idToFarm[farmId].undistributed = tempFarm.undistributed.sub(
            paybackAmount
        );
        emit FarmClose(farmId, paybackAmount);
    }

    function getListingFee() public view returns (uint256) {
        return LISTING_FEE;
    }

    function getFarms(uint256 fromIndex, uint256 limit)
        public
        view
        returns (Farm[] memory)
    {
        uint256 farmCount = _farmCount.current();
        uint256 listCount = farmCount.sub(fromIndex);
        limit = limit > 10 ? 10 : limit;
        limit = limit > listCount ? listCount : limit;
        Farm[] memory farms = new Farm[](limit);
        uint256 listIndex = 0;
        for (uint256 i = fromIndex; listIndex < listCount; i++) {
            farms[listIndex] = _idToFarm[i];
            listIndex++;
        }
        return farms;
    }

    function getFarm(uint256 itemId) public view returns (Farm memory) {
        return _idToFarm[itemId];
    }
}
