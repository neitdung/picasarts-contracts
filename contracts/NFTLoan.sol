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

contract NFTLoan is HubChild {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter private _itemCount;

    mapping(uint256 => Covenant) private _idToCovenant;
    mapping(uint256 => Proposal) private _idToProposal;
    mapping(address => uint256) private _loanAccepted;
    mapping(address => uint256) private _loanLiquidated;
    
    bytes4 public constant ERC721INTERFACE = type(IERC721).interfaceId;
    bytes4 public constant ERC2981INTERFACE = type(IERC2981).interfaceId;

    enum CovenantStatus {
        LISTING,
        LOCKED,
        ENDED
    }

    struct Covenant {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address ftContract;
        uint256 amount;
        uint256 profit;
        uint256 timeExpired;
        uint256 duration;
        CovenantStatus status;
        address borrower;
        address lender;
        bool isLatest;
    }

    struct Proposal {
        uint256 itemId;
        uint256 profit;
        uint256 timeExpired;
    }

    event CovenantListed(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 duration,
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
        uint256 duration
    );

    event CovenantPayOff(
        uint256 itemId,
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit
    );

    event CovenantLiquidate(
        uint256 itemId,
        address nftContract,
        uint256 tokenId
    );

    event CovenantAccept(
        uint256 itemId,
        address lender,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 timeExpired
    );

    event ProposalEdited(uint256 itemId, uint256 profit, uint256 timeExpired);

    event ProposalAccepted(uint256 itemId, uint256 profit, uint256 timeExpired);

    constructor(uint256 fee, address hub) {
        RATE_FEE = fee;
        setHub(hub);
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

    // List the NFT on the marketplace
    function list(
        address nftContract,
        uint256 tokenId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 duration
    ) public nonReentrant {
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
            duration,
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
            duration,
            uint8(CovenantStatus.LISTING),
            msg.sender,
            address(0)
        );
        _itemCount.increment();
    }

    function unlist(uint256 itemId)
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

    function edit(
        uint256 itemId,
        address ftContract,
        uint256 amount,
        uint256 profit,
        uint256 duration
    ) external onlyBorrower(itemId) nonReentrant {
        require(
            _idToCovenant[itemId].status == CovenantStatus.LISTING,
            "Loan covenant is not listing."
        );
        Covenant storage loanCovenant = _idToCovenant[itemId];

        loanCovenant.ftContract = ftContract;
        loanCovenant.amount = amount;
        loanCovenant.profit = profit;
        loanCovenant.duration = duration;
        emit CovenantEdited(itemId, ftContract, amount, profit, duration);
    }

    function extend(
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
            timeAdd
        );
        emit ProposalEdited(itemId, profit, proposal.timeExpired);
    }

    function accept(uint256 itemId)
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

    function lend(uint256 itemId) public payable nonReentrant {
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

        if (loanCovenant.ftContract == address(0)) {
            require(msg.value == loanCovenant.amount, "Loan amount not exact");
        }
        sendAssets(
            msg.sender,
            loanCovenant.borrower,
            loanCovenant.ftContract,
            loanCovenant.amount
        );

        loanCovenant.lender = msg.sender;
        uint256 timeAdd = loanCovenant.duration;
        loanCovenant.timeExpired = timeAdd+block.timestamp;
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

    function payoff(uint256 itemId)
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
        uint256 fee = _feeOf(msg.sender, loanCovenant.ftContract);
        fee = loanCovenant.profit.mul(fee).div(DENOMINATOR);
        if (loanCovenant.ftContract == address(0)) {
            require(
                msg.value == totalPaid,
                "You must add exact amount and profit."
            );
        }
        if (
            ERC165Checker.supportsInterface(
                loanCovenant.nftContract,
                ERC2981INTERFACE
            )
        ) {
            (address creator, uint256 royaltyAmount) = IERC2981(
                loanCovenant.nftContract
            ).royaltyInfo(loanCovenant.tokenId, loanCovenant.profit);
            if (royaltyAmount > 0) {
                sendAssets(
                    msg.sender,
                    creator,
                    loanCovenant.ftContract,
                    royaltyAmount
                );
                sendAssets(
                    msg.sender,
                    loanCovenant.lender,
                    loanCovenant.ftContract,
                    totalPaid.sub(royaltyAmount.add(fee))
                );
            } else {
                sendAssets(
                    msg.sender,
                    loanCovenant.lender,
                    loanCovenant.ftContract,
                    totalPaid.sub(fee)
                );
            }
        } else {
            sendAssets(
                msg.sender,
                loanCovenant.lender,
                loanCovenant.ftContract,
                totalPaid.sub(fee)
            );
        }

        sendAssets(msg.sender, hubAddr, loanCovenant.ftContract, fee);

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

    function getLoanData(address contractAddress, uint256 tokenId)
        public
        view
        returns (Covenant memory, Proposal memory)
    {
        Covenant memory covenant;
        Proposal memory proposal;

        uint256 cCount = _itemCount.current();
        for (uint256 i = 0; i < cCount; i++) {
            if (
                _idToCovenant[i].nftContract == contractAddress &&
                _idToCovenant[i].tokenId == tokenId &&
                _idToCovenant[i].isLatest
            ) {
                covenant = _idToCovenant[i];
                proposal = _idToProposal[i];
                break;
            }
        }

        return (covenant, proposal);
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
