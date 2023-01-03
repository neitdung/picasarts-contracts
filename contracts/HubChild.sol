// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './interfaces/IHubChild.sol';
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract HubChild is IHubChild, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    EnumerableSet.AddressSet internal _acceptTokens;
    EnumerableMap.AddressToUintMap internal _addressFees;

    uint256 public RATE_FEE;
    uint256 public constant DENOMINATOR = 10000;
    address public hubAddr;

    modifier isAcceptToken(address tokenAddr) {
        require(
            tokenAddr == address(0) || _acceptTokens.contains(tokenAddr),
            "Token is not accepted"
        );
        _;
    }

    modifier onlyHub() {
        require(
            msg.sender == hubAddr,
            "Must be hub contract"
        );
        _;
    }

    //IHubChild implement
    function setHub(address hub) public override onlyOwner {
        hubAddr = hub;
    }

    function addAcceptToken(address tokenAddr) external override  onlyHub {
        _acceptTokens.add(tokenAddr);
    }

    function removeToken(address tokenAddr) external override onlyHub {
        _acceptTokens.remove(tokenAddr);
    }

    function getRateFee() external override view returns (uint256) {
        return RATE_FEE;
    }

    function addWhitelistAddress(address whitelistAddress, uint256 fee)
        external
        override
        onlyHub
    {
        _addressFees.set(whitelistAddress, fee);
    }

    function removeWhitelistAddress(address whitelistAddress)
        external
        override
        onlyHub
    {
        _addressFees.remove(whitelistAddress);
    }

    function getWhitelist()
        external
        view
        override
        returns (WhitelistVars[] memory)
    {
        uint256 len = _addressFees.length();
        WhitelistVars[] memory list = new WhitelistVars[](len);
        
        for (uint256 i =0; i <len; i++) {
            (address addr, uint256 fee) = _addressFees.at(i);
            list[i] = WhitelistVars(addr, fee);
        }
        return list;
    }

    function setRateFee(uint256 rateFee) external override onlyHub {
        require(rateFee < DENOMINATOR, "Fee numerator must less than 100%");
        RATE_FEE = rateFee;
    }

    struct FeeVars {
        bool exists;
        uint256 value;
    }

    function _feeOf(address walletAddress, address tokenAddress)
        internal
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