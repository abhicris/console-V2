// SPDX-License-Identifier: MIT

/// @title ERC721 ConsoleEditionV1
/// @author https://github.com/chirag-bgh
/// @notice Edition contract 

pragma solidity 0.8.17;

import "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
import "ERC721A-Upgradeable/ERC721AStorage.sol";
import "./utils/OwnableRoles.sol";


contract ERC721ConsoleEdittion {

    /// @dev a role every minter module must have in order to mint new tokens.
    uint256 public constant minterRole = _ROLE_1;

    /// @dev role for admin actions
    uint256 public constant adminRole = _ROLE_0;


}


