// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721ConsoleDrop} from "../../src/ERC721ConsoleDrop.sol";

contract MockConsoleDrop is ERC721ConsoleDrop {
    function mint(uint256 quantity) external payable {
        _mint(msg.sender, quantity);
    }
}
