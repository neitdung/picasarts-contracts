// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IHub.sol";

interface IHubChild is IHub {
    struct WhitelistVars {
        address addr;
        uint256 fee;
    }
    function setHub(address hub) external;
    function feeOf(address walletAddress, address tokenAddress)
        external
        view
        returns (uint256);

    function getTokenFee(address tokenAddress) external view returns (uint256);

    function getAcceptTokens() external view returns (address[] memory);
    function getRateFee() external view returns (uint256);

    function getWhitelist()
        external
        view
        returns (WhitelistVars[] memory);
}
