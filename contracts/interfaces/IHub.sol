// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

interface IHub {
    function addAcceptToken(address tokenAddr) external;
    function removeToken(address tokenAddr) external;
    function addWhitelistAddress(address whitelistAddress, uint256 fee) external;
    function removeWhitelistAddress(address whitelistAddress) external;
    function setRateFee(uint256 rateFee) external;
}