// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "./interfaces/IERC4907.sol";
import "./HubChild.sol";

contract Rental is HubChild {
    using Counters for Counters.Counter;
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
        UNLISTED
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
        uint256 cycleTime;
        uint256 cycleEnded;
        CovenantStatus status;
        address lender;
    }

    constructor(uint256 fee, address hub) {
        RATE_FEE = fee;
        setHub(hub);
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

    modifier rentAvailable(uint256 itemId) {
        require(
            _idToCovenant[itemId].status != CovenantStatus.LISTING ||
                (_idToProfile[itemId].startTime +
                    _idToProfile[itemId].duration *
                    _idToCovenant[itemId].cycleTime >
                    block.timestamp &&
                    _idToCovenant[itemId].status == CovenantStatus.RENTING),
            "Not time for rent"
        );
        _;
    }

    function list(
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 releaseFrequency,
        uint256 cycleTime,
        uint256 cycleEnded
    ) public nonReentrant {
        require(
            releaseFrequency > 0 && cycleTime > 0,
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
            cycleTime,
            cycleEnded,
            CovenantStatus.LISTING,
            msg.sender
        );

        _idToProfile[itemId] = CovenantProfile(address(0), 0, 0, 0);
    }

    function relist(
        uint256 itemId,
        address ftContract,
        uint256 releaseFrequency,
        uint256 cycleTime,
        uint256 cycleEnded
    ) public nonReentrant {
        require(
            _idToCovenant[itemId].status == CovenantStatus.UNLISTED,
            "Covenant must unlisted before"
        );
        require(
            releaseFrequency > 0 && cycleTime > 0,
            "Release frequency must greater than 0"
        );
        IERC721(_idToCovenant[itemId].nftContract).transferFrom(
            msg.sender,
            address(this),
            _idToCovenant[itemId].tokenId
        );

        _idToCovenant[itemId].ftContract = ftContract;
        _idToCovenant[itemId].releaseFrequency = releaseFrequency;
        _idToCovenant[itemId].cycleTime = cycleTime;
        _idToCovenant[itemId].cycleEnded = cycleEnded;
        _idToCovenant[itemId].status = CovenantStatus.LISTING;
        _idToCovenant[itemId].lender = msg.sender;
        _idToProfile[itemId] = CovenantProfile(address(0), 0, 0, 0);
    }

    function edit(
        uint256 itemId,
        address ftContract,
        uint256 releaseFrequency,
        uint256 cycleTime,
        uint256 cycleEnded
    ) external onlyLender(itemId) rentAvailable(itemId) nonReentrant {
        Covenant storage rentalCovenant = _idToCovenant[itemId];

        rentalCovenant.ftContract = ftContract;
        rentalCovenant.releaseFrequency = releaseFrequency;
        rentalCovenant.cycleTime = cycleTime;
        rentalCovenant.cycleEnded = cycleEnded;

        if (
            _idToProfile[itemId].duration != _idToProfile[itemId].withdrawRound
        ) {
            internalWithdraw(itemId);
        }

        _idToProfile[itemId] = CovenantProfile(address(0), 0, 0, 0);
    }

    function unlist(uint256 itemId)
        external
        onlyLender(itemId)
        rentAvailable(itemId)
        nonReentrant
    {
        Covenant storage rentalCovenant = _idToCovenant[itemId];
        IERC721(rentalCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            rentalCovenant.tokenId
        );
        if (
            _idToProfile[itemId].duration != _idToProfile[itemId].withdrawRound
        ) {
            internalWithdraw(itemId);
        }

        _idToProfile[itemId] = CovenantProfile(address(0), 0, 0, 0);
        rentalCovenant.status = CovenantStatus.UNLISTED;
    }

    function rent(uint256 itemId, uint256 amount) public payable nonReentrant {
        require(
            _idToCovenant[itemId].lender != msg.sender,
            "Sender must be not lender"
        );

        require(
            _idToCovenant[itemId].status == CovenantStatus.RENTING ||
                _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Not accepted state"
        );
        Covenant storage rentalCovenant = _idToCovenant[itemId];
        uint256 duration = amount / rentalCovenant.releaseFrequency;
        uint256 realAmount = duration * rentalCovenant.releaseFrequency;
        uint256 refund = amount - realAmount;

        uint256 startTime = block.timestamp;
        if (_idToCovenant[itemId].status == CovenantStatus.RENTING) {
            require(
                _idToProfile[itemId].startTime +
                    _idToProfile[itemId].duration *
                    _idToCovenant[itemId].cycleTime >
                    block.timestamp,
                "Rental covenant must be ended"
            );
            if (
                _idToProfile[itemId].duration !=
                _idToProfile[itemId].withdrawRound
            ) {
                startTime -=
                    _idToProfile[itemId].duration *
                    rentalCovenant.cycleTime;
                duration += _idToProfile[itemId].duration;
            }
        }

        if (rentalCovenant.ftContract == address(0)) {
            require(msg.value == amount, "Rental amount not exact");
            if (refund > 0) {
                sendAssets(
                    address(this),
                    msg.sender,
                    rentalCovenant.ftContract,
                    refund
                );
            }
        } else {
            sendAssets(
                msg.sender,
                address(this),
                rentalCovenant.ftContract,
                realAmount
            );
        }

        IERC4907(rentalCovenant.nftContract).setUser(
            rentalCovenant.tokenId,
            msg.sender,
            uint96(duration * rentalCovenant.cycleTime + startTime)
        );
        rentalCovenant.status = CovenantStatus.RENTING;
        _idToProfile[itemId].borrower = msg.sender;
        _idToProfile[itemId].startTime = startTime;
        _idToProfile[itemId].duration = duration;
    }

    function topup(uint256 itemId, uint256 amount)
        public
        payable
        onlyBorrower(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.RENTING,
            "Rental covenant must be renting."
        );

        Covenant storage rentalCovenant = _idToCovenant[itemId];
        uint256 duration = amount / rentalCovenant.releaseFrequency;
        uint256 realAmount = duration * rentalCovenant.releaseFrequency;
        uint256 refund = amount - realAmount;

        if (rentalCovenant.ftContract == address(0)) {
            require(msg.value == amount, "Rental amount not exact");
            if (refund > 0) {
                sendAssets(
                    address(this),
                    msg.sender,
                    rentalCovenant.ftContract,
                    refund
                );
            }
        } else {
            sendAssets(
                msg.sender,
                address(this),
                rentalCovenant.ftContract,
                realAmount
            );
        }
        duration += _idToProfile[itemId].duration;
        IERC4907(rentalCovenant.nftContract).setUser(
            rentalCovenant.tokenId,
            msg.sender,
            uint96(duration * rentalCovenant.cycleTime + _idToProfile[itemId].startTime)
        );
        rentalCovenant.status = CovenantStatus.RENTING;
        _idToProfile[itemId].borrower = msg.sender;
        _idToProfile[itemId].duration = duration;
    }

    function cancel(uint256 itemId)
        public
        payable
        onlyBorrower(itemId)
        nonReentrant
    {
        uint256 currentTime = block.timestamp;
        uint256 currentCycle = (currentTime - _idToProfile[itemId].startTime) /
            _idToCovenant[itemId].cycleTime;
        currentCycle++;

        require(
            (_idToCovenant[itemId].status == CovenantStatus.RENTING ||
                _idToCovenant[itemId].status == CovenantStatus.REDEEM) &&
                currentCycle < _idToProfile[itemId].duration,
            "Rental covenant must be renting."
        );

        Covenant storage rentalCovenant = _idToCovenant[itemId];
        uint256 refund = rentalCovenant.releaseFrequency *
            (_idToProfile[itemId].duration - currentCycle);

        // refund user
        sendAssets(
            address(this),
            _idToProfile[itemId].borrower,
            rentalCovenant.ftContract,
            refund
        );
        uint256 amount = rentalCovenant.releaseFrequency * currentCycle;
        uint256 fee = _feeOf(rentalCovenant.lender, rentalCovenant.ftContract);
        fee = (amount * fee) / DENOMINATOR;
        if (
            ERC165Checker.supportsInterface(
                rentalCovenant.nftContract,
                ERC2981INTERFACE
            )
        ) {
            (address creator, uint256 royaltyAmount) = IERC2981(
                rentalCovenant.nftContract
            ).royaltyInfo(rentalCovenant.tokenId, amount);
            if (creator != rentalCovenant.lender && royaltyAmount > 0) {
                sendAssets(
                    address(this),
                    creator,
                    rentalCovenant.ftContract,
                    royaltyAmount
                );
                sendAssets(
                    address(this),
                    rentalCovenant.lender,
                    rentalCovenant.ftContract,
                    amount - fee - royaltyAmount
                );
            } else {
                sendAssets(
                    address(this),
                    rentalCovenant.lender,
                    rentalCovenant.ftContract,
                    amount - fee
                );
            }
        } else {
            sendAssets(
                address(this),
                rentalCovenant.lender,
                rentalCovenant.ftContract,
                amount - fee
            );
        }
        sendAssets(
            address(this),
            owner(),
            rentalCovenant.ftContract,
            amount - fee
        );
        IERC4907(rentalCovenant.nftContract).setUser(
            rentalCovenant.tokenId,
            msg.sender,
            uint96(currentCycle *
                rentalCovenant.cycleTime +
                _idToProfile[itemId].startTime)
        );
        _idToProfile[itemId].duration = currentCycle;
    }

    function withdraw(uint256 itemId)
        public
        payable
        onlyLender(itemId)
        nonReentrant
    {
        internalWithdraw(itemId);
    }

    function internalWithdraw(uint256 itemId) private nonReentrant {
        uint256 currentTime = block.timestamp;
        uint256 currentCycle = (currentTime - _idToProfile[itemId].startTime) /
            _idToCovenant[itemId].cycleTime;
        currentCycle = currentCycle < _idToProfile[itemId].duration
            ? currentCycle
            : _idToProfile[itemId].duration;
        require(
            currentCycle > _idToProfile[itemId].withdrawRound,
            "You withdraw all available"
        );

        Covenant storage rentalCovenant = _idToCovenant[itemId];

        uint256 amount = rentalCovenant.releaseFrequency *
            (currentCycle - _idToProfile[itemId].withdrawRound);
        uint256 fee = _feeOf(rentalCovenant.lender, rentalCovenant.ftContract);
        fee = (amount * fee) / DENOMINATOR;
        if (
            ERC165Checker.supportsInterface(
                rentalCovenant.nftContract,
                ERC2981INTERFACE
            )
        ) {
            (address creator, uint256 royaltyAmount) = IERC2981(
                rentalCovenant.nftContract
            ).royaltyInfo(rentalCovenant.tokenId, amount);
            if (creator != rentalCovenant.lender && royaltyAmount > 0) {
                sendAssets(
                    address(this),
                    creator,
                    rentalCovenant.ftContract,
                    royaltyAmount
                );
                sendAssets(
                    address(this),
                    rentalCovenant.lender,
                    rentalCovenant.ftContract,
                    amount - fee - royaltyAmount
                );
            } else {
                sendAssets(
                    address(this),
                    rentalCovenant.lender,
                    rentalCovenant.ftContract,
                    amount - fee
                );
            }
        } else {
            sendAssets(
                address(this),
                rentalCovenant.lender,
                rentalCovenant.ftContract,
                amount - fee
            );
        }
        sendAssets(
            address(this),
            owner(),
            rentalCovenant.ftContract,
            amount - fee
        );

        _idToProfile[itemId].withdrawRound = currentCycle;
    }

    function stop(uint256 itemId)
        public
        payable
        onlyLender(itemId)
        nonReentrant
    {
        uint256 currentTime = block.timestamp;
        uint256 endCycle = (currentTime - _idToProfile[itemId].startTime) /
            _idToCovenant[itemId].cycleTime;
        endCycle += _idToCovenant[itemId].cycleEnded;
        endCycle = endCycle < _idToProfile[itemId].duration
            ? endCycle
            : _idToProfile[itemId].duration;

        Covenant storage rentalCovenant = _idToCovenant[itemId];
        uint256 refund = _idToCovenant[itemId].releaseFrequency *
            (_idToProfile[itemId].duration - endCycle);
        if (refund > 0) {
            sendAssets(
                address(this),
                _idToProfile[itemId].borrower,
                rentalCovenant.ftContract,
                refund
            );
        }

        _idToProfile[itemId].duration = endCycle;
        rentalCovenant.status = CovenantStatus.REDEEM;
    }

    function redeem(uint256 itemId) external onlyLender(itemId) nonReentrant {
        require(
            _idToProfile[itemId].startTime +
                _idToProfile[itemId].duration *
                _idToCovenant[itemId].cycleTime <
                block.timestamp &&
                _idToCovenant[itemId].status == CovenantStatus.REDEEM,
            "Covenant must be redeem"
        );
        Covenant storage rentalCovenant = _idToCovenant[itemId];
        IERC721(rentalCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            rentalCovenant.tokenId
        );
        if (
            _idToProfile[itemId].duration != _idToProfile[itemId].withdrawRound
        ) {
            internalWithdraw(itemId);
        }

        _idToProfile[itemId] = CovenantProfile(address(0), 0, 0, 0);
        rentalCovenant.status = CovenantStatus.UNLISTED;
    }

    function getCovenants() public view returns (Covenant[] memory) {
        uint256 covenantCount = _itemCount.current();

        Covenant[] memory covenants = new Covenant[](covenantCount);
        uint256 covenantIndex = 0;
        for (uint256 i = 0; i < covenantCount; i++) {
            covenants[covenantIndex] = _idToCovenant[i];
            covenantIndex++;
        }
        return covenants;
    }

    function getCovenantsByAddress(address addr)
        public
        view
        returns (Covenant[] memory)
    {
        uint256 covenantCount = _itemCount.current();
        uint256 myListedCovenantCount = 0;
        for (uint256 i = 0; i < covenantCount; i++) {
            if (
                _idToProfile[i].borrower == addr ||
                _idToCovenant[i].lender == addr
            ) {
                myListedCovenantCount++;
            }
        }

        Covenant[] memory covenants = new Covenant[](covenantCount);
        uint256 covenantIndex = 0;
        for (uint256 i = 0; i < myListedCovenantCount; i++) {
            if (
                _idToProfile[i].borrower == addr ||
                _idToCovenant[i].lender == addr
            ) {
                covenants[covenantIndex] = _idToCovenant[i];
                covenantIndex++;
            }
        }
        return covenants;
    }

    function getCovenant(uint256 itemId)
        public
        view
        returns (Covenant memory, CovenantProfile memory)
    {
        Covenant memory covenant = _idToCovenant[itemId];
        CovenantProfile memory profile = _idToProfile[itemId];
        return (covenant, profile);
    }

    function getRentalData(address contractAddress, uint256 tokenId)
        public
        view
        returns (Covenant memory)
    {
        Covenant memory covenant;
        uint256 cCount = _itemCount.current();
        for (uint256 i = 0; i < cCount; i++) {
            if (
                _idToCovenant[i].nftContract == contractAddress &&
                _idToCovenant[i].tokenId == tokenId
            ) {
                covenant = _idToCovenant[i];
                break;
            }
        }

        return covenant;
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
