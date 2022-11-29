// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./HubChild.sol";

contract Rental is HubChild {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter private _itemCount;
    mapping(uint256 => Covenant) private _idToCovenant;
    mapping(uint256 => CovenantProfile) private _idToProfile;
    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;
    bytes4 public constant ERC2981INTERFACE = type(IERC2981).interfaceId;

    enum CovenantStatus {
        NOT_INITIAL,
        LISTING,
        RENTING,
        REDEEM,
        ENDED
    }

    struct CovenantProfile {
        address borrower;
        uint256 startTime;
        uint256 duration;
        uint256 withdrawRound;
    }

    struct Covenant {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address ftContract;
        uint256 releaseFrequency;
        uint256 releaseTimes;
        uint256 cycleEnded;
        CovenantStatus status;
        address lender;
    }

    constructor(uint256 fee) {
        require(fee < DENOMINATOR, "Fee numerator must less than 100%");
        RATE_FEE = fee;
    }

    modifier onlyBorrower(uint256 itemId) {
        require(
            _idToProfile[itemId].borrower == msg.sender,
            "Sender is not borrower"
        );
        _;
    }

    modifier onlyLender(uint256 itemId) {
        require(
            _idToCovenant[itemId].lender == msg.sender,
            "Sender is not lender"
        );
        _;
    }

    function listCovenant(
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 releaseFrequency,
        uint256 releaseTimes,
        uint256 cycleEnded
    ) public nonReentrant {
        require(
            releaseFrequency > 0 && releaseTimes > 0,
            "Release frequency must greater than 0"
        );
        require(
            ERC165Checker.supportsInterface(nftContract, ERC721INTERFACE),
            "Contract needs to be ERC721"
        );

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        _itemCount.increment();
        uint256 itemId = _itemCount.current();

        _idToCovenant[itemId] = Covenant(
            itemId,
            nftContract,
            tokenId,
            ftContract,
            releaseFrequency,
            releaseTimes,
            cycleEnded,
            CovenantStatus.LISTING,
            msg.sender
        );

        _idToProfile[itemId] = CovenantProfile(
            address(0),
            block.timestamp,
            0,
            0
        );
    }

    function relistCovenant(
        uint256 itemId,
        uint256 releaseFrequency,
        uint256 releaseTimes,
        uint256 cycleEnded
    ) public nonReentrant {
        require(
            _idToCovenant[itemId].status == CovenantStatus.ENDED,
            "Covenant must ended before"
        );
        require(
            releaseFrequency > 0 && releaseTimes > 0,
            "Release frequency must greater than 0"
        );

        _idToCovenant[itemId].releaseFrequency = releaseFrequency;
        _idToCovenant[itemId].releaseTimes = releaseTimes;
        _idToCovenant[itemId].cycleEnded = cycleEnded;
        _idToCovenant[itemId].status = CovenantStatus.LISTING;
        _idToCovenant[itemId].lender = msg.sender;
    }

    function editListingItem(
        uint256 itemId,
        address ftContract,
        uint256 releaseFrequency,
        uint256 releaseTimes,
        uint256 cycleEnded
    ) external onlyLender(itemId) nonReentrant {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Rental covenant is not listing."
        );
        Covenant storage rentalCovenant = _idToCovenant[itemId];

        rentalCovenant.ftContract = ftContract;
        rentalCovenant.releaseFrequency = releaseFrequency;
        rentalCovenant.releaseTimes = releaseTimes;
        rentalCovenant.cycleEnded = cycleEnded;
    }

    function endListedItem(uint256 itemId)
        external
        onlyLender(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Rental covenant is not listing."
        );
        Covenant storage rentalCovenant = _idToCovenant[itemId];
        IERC721(rentalCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            rentalCovenant.tokenId
        );
        rentalCovenant.status = CovenantStatus.ENDED;
    }

    function rent(uint256 itemId, uint256 amount, bool isStreaming) public payable nonReentrant {
        require(
            _idToCovenant[itemId].lender != msg.sender,
            "Sender must be not lender"
        );
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Rental covenant must be lesting."
        );

        Covenant storage rentalCovenant = _idToCovenant[itemId];
        uint256 duration = amount.div(rentalCovenant.releaseFrequency);
        uint256 realAmount = duration.mul(rentalCovenant.releaseFrequency);
        if (rentalCovenant.ftContract == address(0)) {
            require(msg.value == amount, "Rental amount not exact");
            sendAssets(
                address(this),
                msg.sender,
                address(0),
                amount.sub(realAmount)
            );
        }
        if (!isStreaming) {
            uint256 fee = _feeOf(msg.sender, rentalCovenant.ftContract);
            fee = realAmount.mul(fee).div(DENOMINATOR);
            if (
                ERC165Checker.supportsInterface(
                    rentalCovenant.nftContract,
                    ERC2981INTERFACE
                )
            ) {
                (address creator, uint256 royaltyAmount) = IERC2981(
                    rentalCovenant.nftContract
                ).royaltyInfo(rentalCovenant.tokenId, realAmount);
                if (royaltyAmount > 0) {
                    sendAssets(
                        msg.sender,
                        creator,
                        rentalCovenant.ftContract,
                        royaltyAmount
                    );
                    sendAssets(
                        msg.sender,
                        rentalCovenant.lender,
                        rentalCovenant.ftContract,
                        realAmount.sub(royaltyAmount.add(fee))
                    );
                } else {
                    sendAssets(
                        msg.sender,
                        rentalCovenant.lender,
                        rentalCovenant.ftContract,
                        realAmount.sub(fee)
                    );
                }
            } else {
                sendAssets(
                    msg.sender,
                    rentalCovenant.lender,
                    rentalCovenant.ftContract,
                    realAmount.sub(fee)
                );
            }
        } else {
            // _idToProfile[itemId].isStreaming = true;
        }
        _idToCovenant[itemId].status = CovenantStatus.RENTING;
        _idToProfile[itemId].borrower = msg.sender;
    }

    // function payOff(uint256 itemId)
    //     external
    //     payable
    //     onlyBorrower(itemId)
    //     nonReentrant
    // {
    //     require(
    //         _idToCovenant[itemId].status == CovenantStatus.LOCKED &&
    //             _idToCovenant[itemId].timeExpired > block.timestamp,
    //         "Time is up. Contact lender for extend time."
    //     );
    //     Covenant storage rentalCovenant = _idToCovenant[itemId];
    //     uint256 totalPaid = rentalCovenant.amount;
    //     totalPaid = totalPaid.add(rentalCovenant.profit);
    //     uint256 fee = _feeOf(msg.sender, rentalCovenant.ftContract);
    //     fee = rentalCovenant.profit.mul(fee).div(DENOMINATOR);
    //     if (rentalCovenant.ftContract == address(0)) {
    //         require(
    //             msg.value == totalPaid,
    //             "You must add exact amount and profit."
    //         );
    //     }


    //     sendAssets(msg.sender, owner(), rentalCovenant.ftContract, fee);

    //     IERC721(rentalCovenant.nftContract).transferFrom(
    //         address(this),
    //         msg.sender,
    //         rentalCovenant.tokenId
    //     );
    //     rentalCovenant.status = CovenantStatus.ENDED;
    //     rentalCovenant.isLatest = false;
    //     // emit CovenantPayOff(
    //     //     itemId,
    //     //     rentalCovenant.nftContract,
    //     //     rentalCovenant.tokenId,
    //     //     rentalCovenant.ftContract,
    //     //     rentalCovenant.amount,
    //     //     rentalCovenant.profit
    //     // );
    // }

    // function liquidate(uint256 itemId)
    //     external
    //     payable
    //     onlyLender(itemId)
    //     nonReentrant
    // {
    //     require(
    //         _idToCovenant[itemId].status == CovenantStatus.LOCKED &&
    //             _idToCovenant[itemId].timeExpired < block.timestamp,
    //         "Not time for liquidate covenant"
    //     );
    //     Covenant storage rentalCovenant = _idToCovenant[itemId];
    //     IERC721(rentalCovenant.nftContract).transferFrom(
    //         address(this),
    //         msg.sender,
    //         rentalCovenant.tokenId
    //     );
    //     rentalCovenant.status = CovenantStatus.ENDED;
    //     rentalCovenant.isLatest = false;
    //     // emit CovenantLiquidate(
    //     //     itemId,
    //     //     rentalCovenant.nftContract,
    //     //     rentalCovenant.tokenId
    //     // );
    // }

    // function getCovenants() public view returns (Covenant[] memory) {
    //     uint256 covenantCount = _itemCount.current();

    //     Covenant[] memory covenants = new Covenant[](covenantCount);
    //     uint256 covenantIndex = 0;
    //     for (uint256 i = 0; i < covenantCount; i++) {
    //         covenants[covenantIndex] = _idToCovenant[i];
    //         covenantIndex++;
    //     }
    //     return covenants;
    // }

    // function getCovenantsByAddress(address addr)
    //     public
    //     view
    //     returns (Covenant[] memory)
    // {
    //     uint256 covenantCount = _itemCount.current();
    //     uint256 myListedCovenantCount = 0;
    //     for (uint256 i = 0; i < covenantCount; i++) {
    //         if (
    //             _idToCovenant[i].borrower == addr ||
    //             _idToCovenant[i].lender == addr
    //         ) {
    //             myListedCovenantCount++;
    //         }
    //     }

    //     Covenant[] memory covenants = new Covenant[](covenantCount);
    //     uint256 covenantIndex = 0;
    //     for (uint256 i = 0; i < myListedCovenantCount; i++) {
    //         if (
    //             _idToCovenant[i].borrower == addr ||
    //             _idToCovenant[i].lender == addr
    //         ) {
    //             covenants[covenantIndex] = _idToCovenant[i];
    //             covenantIndex++;
    //         }
    //     }
    //     return covenants;
    // }

    // function getCovenant(uint256 itemId)
    //     public
    //     view
    //     returns (Covenant memory, CovenantProfile memory)
    // {
    //     Covenant memory covenant = _idToCovenant[itemId];
    //     CovenantProfile memory profile = _idToProfile[itemId];
    //     return (covenant, profile);
    // }

    // function getRentalData(address contractAddress, uint256 tokenId)
    //     public
    //     view
    //     returns (Covenant memory)
    // {
    //     Covenant memory covenant;
    //     uint256 cCount = _itemCount.current();
    //     for (uint256 i = 0; i < cCount; i++) {
    //         if (
    //             _idToCovenant[i].nftContract == contractAddress &&
    //             _idToCovenant[i].tokenId == tokenId &&
    //             _idToCovenant[i].isLatest
    //         ) {
    //             covenant = _idToCovenant[i];
    //             break;
    //         }
    //     }

    //     return covenant;
    // }

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
