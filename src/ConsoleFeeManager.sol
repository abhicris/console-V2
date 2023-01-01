// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { IConsoleFeeManager } from "./interfaces/IConsoleFeeManager.sol";

/**
 * @title ConsoleFeeManager
 * @author https://github.com/chirag-bgh
 */
contract ConsoleFeeManager is IConsoleFeeManager, OwnableRoles {
   
    /**
     * @dev This is the denominator, in basis points (BPS), for platform fees.
     */
    uint16 private constant _MAX_BPS = 10_000;
    /**
     * @dev The protocol's address that receives platform fees.
     */
    address public override consoleFeeAddress;

    /**
     * @dev The numerator of the platform fee.
     */
    uint16 public override platformFeeBPS;

    constructor(address consoleFeeAddress_, uint16 platformFeeBPS_)
        onlyValidConsoleFeeAddress(consoleFeeAddress_)
        onlyValidPlatformFeeBPS(platformFeeBPS_)
    {
        consoleFeeAddress = consoleFeeAddress_;
        platformFeeBPS = platformFeeBPS_;

        _initializeOwner(msg.sender);
    }

    function setConsoleFeeAddress(address consoleFeeAddress_)
        external
        onlyOwner
        onlyValidConsoleFeeAddress(consoleFeeAddress_)
    {
        consoleFeeAddress = consoleFeeAddress_;
        emit consoleFeeAddressSet(consoleFeeAddress_);
    }

    function setPlatformFeeBPS(uint16 platformFeeBPS_) external onlyOwner onlyValidPlatformFeeBPS(platformFeeBPS_) {
        platformFeeBPS = platformFeeBPS_;
        emit PlatformFeeSet(platformFeeBPS_);
    }

    function platformFee(uint128 requiredEtherValue) external view returns (uint128 fee) {
        // Won't overflow, as `requiredEtherValue` is 128 bits, and `platformFeeBPS` is 16 bits.
        unchecked {
            fee = uint128((uint256(requiredEtherValue) * uint256(platformFeeBPS)) / uint256(_MAX_BPS));
        }
    }

    /**
     * @dev Restricts the Console fee address to be address(0).
     * @param consoleFeeAddress_ The Console fee address.
     */
    modifier onlyValidConsoleFeeAddress(address consoleFeeAddress_) {
        if (consoleFeeAddress_ == address(0)) revert InvalidConsoleFeeAddress();
        _;
    }

    /**
     * @dev Restricts the platform fee numerator to not exceed the `_MAX_BPS`.
     * @param platformFeeBPS_ Platform fee amount in bps (basis points).
     */
    modifier onlyValidPlatformFeeBPS(uint16 platformFeeBPS_) {
        if (platformFeeBPS_ > _MAX_BPS) revert InvalidPlatformFeeBPS();
        _;
    }
}
