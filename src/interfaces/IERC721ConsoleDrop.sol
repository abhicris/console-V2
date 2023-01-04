// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC721AUpgradeable } from "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
import { IERC2981Upgradeable } from "openzeppelin-upgradeable/interfaces/IERC2981Upgradeable.sol";
import { IERC165Upgradeable } from "openzeppelin-upgradeable/utils/introspection/IERC165Upgradeable.sol";


/**
 * @dev Interface for ERC721ConsoleDrop.sol
 */
interface IERC721ConsoleDrop is IERC721AUpgradeable, IERC2981Upgradeable {

    // =============================================================
    //                            EVENTS
    // =============================================================

   /**
     * @dev Emitted upon an airdrop.
     * @param to          The recipients of the airdrop.
     * @param quantity    The number of tokens airdropped to each address in `to`.
     * @param fromTokenId The first token ID minted to the first address in `to`.
     */
    event Airdropped(address[] to, uint256 quantity, uint256 fromTokenId);

  /**
   * @notice Emitted when the collection is revealed.
   * @param baseURI The base URI for the collection.
   * @param isRevealed Whether the collection is revealed.
   */
  event URIUpdated(string baseURI, bool isRevealed);


    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev No addresses to airdrop.
     */
    error NoAddressesToAirdrop();



   

}
