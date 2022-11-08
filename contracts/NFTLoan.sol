// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IERC4907.sol";

contract NFTLoan is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeMath for uint96;

    Counters.Counter private _itemCount;
    uint96 private LISTING_FEE;
    uint96 private constant DENOMINATOR = 10000;
    mapping(uint256 => Covenant) private _idToCovenant;

    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;
    bytes4 public constant ERC4907INTERFACE = type(IERC4907).interfaceId;
    address private _owner;

    enum CovenantStatus {
        NOT_LISTED,
        LISTING,
        RENTING,
        ENDED
    }

    struct Covenant {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address ftContract;
        uint256 amount;
        uint256 timeExpired;
        uint256 timeDays;
        CovenantStatus status;
        address borrower;
        address lender;
    }

    event CovenantListed(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeDays,
        uint8 status,
        address borrower,
        address lender
    );

    event CovenantUnlisted(uint256 itemId);

    event CovenantEdited(
        uint256 itemId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeDays
    );

    event CovenantLease(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeExpired,
        uint8 status,
        address borrower,
        address lender
    );

    event CovenantRedeem(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit
    );

    constructor(uint96 fee) {
        require(fee < DENOMINATOR, "Fee numerator must less than 100%");
        _owner = msg.sender;
        LISTING_FEE = fee;
    }

    modifier onlyBorrower(uint256 itemId) {
        require(
            _idToCovenant[itemId].borrower == msg.sender,
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

    function setListingFee(uint96 fee) public onlyOwner {
        require(fee < DENOMINATOR, "Fee numerator must less than 100%");
        LISTING_FEE = fee;
    }

    // List the NFT on the marketplace
    function listCovenant(
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeDays
    ) public payable nonReentrant {
        require(
            amount > 0 && profit > 0,
            "Loan amount and profit must be at least 1"
        );
        require(
            ERC165Checker.supportsInterface(nftContract, ERC721INTERFACE),
            "Contract needs to be ERC721"
        );

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        uint256 itemId = _itemCount.current();
        _idToCovenant[itemId] = Covenant(
            itemId,
            nftContract,
            tokenId,
            ftContract,
            amount,
            profit,
            0,
            timeDays,
            CovenantStatus.LISTING,
            msg.sender,
            address(0),
            true
        );

        _idToProposal[itemId] = Proposal(itemId, 0, 0);

        emit CovenantListed(
            _itemCount.current(),
            nftContract,
            tokenId,
            ftContract,
            amount,
            profit,
            timeDays,
            uint8(CovenantStatus.LISTING),
            msg.sender,
            address(0)
        );
        _itemCount.increment();
    }

    function endListedItem(uint256 itemId)
        external
        onlyBorrower(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Loan covenant is not listing."
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];
        IERC721(loanCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            loanCovenant.tokenId
        );
        loanCovenant.status = CovenantStatus.ENDED;
        loanCovenant.isLatest = false;
        emit CovenantUnlisted(itemId);
    }

    function editListingItem(
        uint256 itemId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeDays
    ) external onlyBorrower(itemId) nonReentrant {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Loan covenant is not listing."
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];

        loanCovenant.ftContract = ftContract;
        loanCovenant.amount = amount;
        loanCovenant.profit = profit;
        loanCovenant.timeDays = timeDays;
        emit CovenantEdited(itemId, ftContract, amount, profit, timeDays);
    }

    function editProposal(
        uint256 itemId,
        uint256 profit,
        uint256 timeAdd
    ) external onlyBorrower(itemId) nonReentrant {
        Proposal storage proposal = _idToProposal[itemId];
        require(
            _idToCovenant[itemId].status == CovenantStatus.LOCKED,
            "Loan covenant is not locked."
        );

        proposal.profit = profit;
        proposal.timeExpired = _idToCovenant[itemId].timeExpired.add(
            timeAdd.mul(1 minutes)
        );
        emit ProposalEdited(itemId, profit, proposal.timeExpired);
    }

    function acceptProposal(uint256 itemId)
        external
        onlyLender(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LOCKED,
            "Loan covenant is not locked."
        );
        require(
            _idToProposal[itemId].timeExpired != 0,
            "There is no proposal for this covenant"
        );

        Covenant storage loanCovenant = _idToCovenant[itemId];
        Proposal storage proposal = _idToProposal[itemId];
        uint256 newProfit = proposal.profit;
        loanCovenant.profit = newProfit.add(loanCovenant.profit);
        loanCovenant.timeExpired = _idToProposal[itemId].timeExpired;
        proposal.timeExpired = 0;
        emit ProposalAccepted(
            itemId,
            loanCovenant.profit,
            loanCovenant.timeExpired
        );
    }

    function acceptCovenant(uint256 itemId) public payable nonReentrant {
        require(
            _idToCovenant[itemId].borrower != msg.sender,
            "Sender must be not borrower"
        );
        require(
            _idToCovenant[itemId].borrower != address(0),
            "Loan covenant is not existed."
        );
        require(
            _idToCovenant[itemId].lender == address(0) &&
                _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Loan covenant is not listing."
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];
        uint256 fee = loanCovenant.amount;
        fee = fee.mul(uint256(LISTING_FEE.div(DENOMINATOR)));
        uint256 sentAmount = loanCovenant.amount.sub(fee);
        sentAmount.sub(fee);
        if (loanCovenant.ftContract == address(0)) {
            require(msg.value == loanCovenant.amount, "Loan amount not exact");
            if (fee > 0) {
                payable(_owner).transfer(fee);
            }
            payable(loanCovenant.borrower).transfer(sentAmount);
        } else {
            if (fee > 0) {
                IERC20(loanCovenant.ftContract).transferFrom(
                    msg.sender,
                    _owner,
                    fee
                );
            }
            IERC20(loanCovenant.ftContract).transferFrom(
                msg.sender,
                loanCovenant.borrower,
                sentAmount
            );
        }

        loanCovenant.lender = msg.sender;
        uint256 timeAdd = loanCovenant.timeDays;
        loanCovenant.timeExpired = timeAdd.mul(1 minutes).add(block.timestamp);
        loanCovenant.status = CovenantStatus.LOCKED;
        _loanAccepted[msg.sender] = _loanAccepted[msg.sender].add(1);
        emit CovenantAccept(
            itemId,
            msg.sender,
            loanCovenant.ftContract,
            loanCovenant.amount,
            loanCovenant.profit,
            loanCovenant.timeExpired
        );
    }

    function payOff(uint256 itemId)
        external
        payable
        onlyBorrower(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LOCKED &&
                _idToCovenant[itemId].timeExpired > block.timestamp,
            "Time is up. Contact lender for extend time."
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];
        uint256 totalPaid = loanCovenant.amount;
        totalPaid = totalPaid.add(loanCovenant.profit);
        if (loanCovenant.ftContract == address(0)) {
            require(
                msg.value == totalPaid,
                "You must add exact amount and profit."
            );
            payable(loanCovenant.lender).transfer(msg.value);
        } else {
            IERC721(loanCovenant.nftContract).transferFrom(
                msg.sender,
                loanCovenant.lender,
                totalPaid
            );
        }
        IERC721(loanCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            loanCovenant.tokenId
        );
        loanCovenant.status = CovenantStatus.ENDED;
        loanCovenant.isLatest = false;
        emit CovenantPayOff(
            itemId,
            loanCovenant.nftContract,
            loanCovenant.tokenId,
            loanCovenant.ftContract,
            loanCovenant.amount,
            loanCovenant.profit
        );
    }

    function liquidate(uint256 itemId)
        external
        payable
        onlyLender(itemId)
        nonReentrant
    {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LOCKED &&
                _idToCovenant[itemId].timeExpired < block.timestamp,
            "Not time for liquidate covenant"
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];
        IERC721(loanCovenant.nftContract).transferFrom(
            address(this),
            msg.sender,
            loanCovenant.tokenId
        );
        loanCovenant.status = CovenantStatus.ENDED;
        loanCovenant.isLatest = false;
        _loanLiquidated[msg.sender] = _loanLiquidated[msg.sender].add(1);
        emit CovenantLiquidate(
            itemId,
            loanCovenant.nftContract,
            loanCovenant.tokenId
        );
    }

    function getListingFee() public view returns (uint96) {
        return LISTING_FEE;
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
                _idToCovenant[i].borrower == addr ||
                _idToCovenant[i].lender == addr
            ) {
                myListedCovenantCount++;
            }
        }

        Covenant[] memory covenants = new Covenant[](covenantCount);
        uint256 covenantIndex = 0;
        for (uint256 i = 0; i < myListedCovenantCount; i++) {
            if (
                _idToCovenant[i].borrower == addr ||
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
        returns (Covenant memory, Proposal memory)
    {
        Covenant memory covenant = _idToCovenant[itemId];
        Proposal memory proposal = _idToProposal[itemId];
        return (covenant, proposal);
    }

    function getUserHealth(address addr)
        public
        view
        returns (uint256, uint256)
    {
        return (_loanAccepted[addr], _loanLiquidated[addr]);
    }

    function getLoanData(address contractAddress, uint256 tokenId) public view returns (Covenant memory) {
        Covenant memory covenant;
        uint256 cCount = _itemCount.current();
        for (uint256 i = 0; i < cCount; i++) {
            if (_idToCovenant[i].nftContract == contractAddress && _idToCovenant[i].tokenId == tokenId && _idToCovenant[i].isLatest) {
                covenant = _idToCovenant[i];
                break;
            }
        }

        return covenant;
    }
}
