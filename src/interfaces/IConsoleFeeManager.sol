// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IConsoleFeeManager
 * @author https://github.com/chirag-bgh
 */
interface IConsoleFeeManager {
    /**
     * @dev Emitted when the `consoleFeeAddress` is changed.
     */
    event ConsoleFeeAddressSet(address consoleFeeAddress);

    /**
     * @dev Emitted when the `platformFeeBPS` is changed.
     */
    event PlatformFeeSet(uint16 platformFeeBPS);

    /**
     * @dev The new `consoleFeeAddress` must not be address(0).
     */
    error InvalidConsoleFeeAddress();

    /**
     * @dev The platform fee numerator must not exceed `_MAX_BPS`.
     */
    error InvalidPlatformFeeBPS();

    /**
     * @dev Sets the `consoleFeeAddress`.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param consoleFeeAddress_ The sound fee address.
     */
    function setConsoleFeeAddress(address consoleFeeAddress_) external;

    /**
     * @dev Sets the `platformFeePBS`.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param platformFeeBPS_ Platform fee amount in bps (basis points).
     */
    function setPlatformFeeBPS(uint16 platformFeeBPS_) external;

    /**
    
     */

    function getConsoleFeeManager() external view returns (address);

    /**
     * @dev The protocol's address that receives platform fees.
     * @return The configured value.
     */
    function consoleFeeAddress() external view returns (address);

    /**
     * @dev The numerator of the platform fee.
     * @return The configured value.
     */
    function platformFeeBPS() external view returns (uint16);

    /**
     * @dev The platform fee for `requiredEtherValue`.
     * @param requiredEtherValue The required Ether value for payment.
     * @return fee The computed value.
     */
    function platformFee(uint128 requiredEtherValue)
        external
        view
        returns (uint128 fee);
}
