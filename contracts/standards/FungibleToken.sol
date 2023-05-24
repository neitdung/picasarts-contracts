// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FungibleToken is ERC20 {
    constructor(string memory name, string memory symbol, address[] memory minters) ERC20(name, symbol) {
        _mint(msg.sender, 10000000000 * 10 ** decimals());
        _mint(minters[1], 2000000000 * 10 ** decimals());
        _mint(minters[2], 3000000000 * 10 ** decimals());
        _mint(minters[3], 4000000000 * 10 ** decimals());
    }
}