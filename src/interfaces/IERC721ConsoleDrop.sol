// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// import {IERC721AUpgradeable} from "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
// import {IERC2981Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
// import {IERC165Upgradeable} from "openzeppelin-contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";
import {IConsoleFeeManager} from "./IConsoleFeeManager.sol";

/**
 * @dev Interface for ERC721ConsoleDrop.sol
 */

interface IERC721ConsoleDrop {
    /// @notice General configuration for NFT Minting and bookkeeping
    struct Configuration {
        /// @dev Total size of edition that can be minted (uint160+64 = 224)
        uint64 editionSize;
        /// @dev Royalty amount in bps (uint224+16 = 240)
        uint16 royaltyBPS;
        /// @dev Funds recipient for sale (new slot, uint160)
        address payable fundsRecipient;
    }

    /// @notice Sales states and configuration
    /// @dev Uses 3 storage slots
    struct SalesConfiguration {
        /// @dev Public sale price (max ether value > 1000 ether with this value)
        uint104 publicSalePrice;
        /// @notice Purchase mint limit per address (if set to 0 === unlimited mints)
        /// @dev Max purchase number per txn (90+32 = 122)
        uint32 maxSalePurchasePerAddress;
        /// @dev uint64 type allows for dates into 292 billion years
        /// @notice Public sale start timestamp (136+64 = 186)
        uint64 publicSaleStart;
        /// @notice Public sale end timestamp (186+64 = 250)
        uint64 publicSaleEnd;
        /// @notice Presale start timestamp
        /// @dev new storage slot
        uint64 presaleStart;
        /// @notice Presale end timestamp
        uint64 presaleEnd;
        /// @notice Presale merkle root
        bytes32 presaleMerkleRoot;
    }

    /// @notice Return value for sales details to use with front-ends
    struct SaleDetails {
        // Synthesized status variables for sale and presale
        bool publicSaleActive;
        bool presaleActive;
        // Price for public sale
        uint256 publicSalePrice;
        // Timed sale actions for public sale
        uint64 publicSaleStart;
        uint64 publicSaleEnd;
        // Timed sale actions for presale
        uint64 presaleStart;
        uint64 presaleEnd;
        // Merkle root (includes address, quantity, and price data for each entry)
        bytes32 presaleMerkleRoot;
        // Limit public sale to a specific number of mints per wallet
        uint256 maxSalePurchasePerAddress;
        // Information about the rest of the supply
        // Total that have been minted
        uint256 totalMinted;
        // The total supply available
        uint256 maxSupply;
    }

    /// @notice Return type of specific mint counts and details per address
    struct AddressMintDetails {
        /// Number of total mints from the given address
        uint256 totalMints;
        /// Number of presale mints from the given address
        uint256 presaleMints;
        /// Number of public mints from the given address
        uint256 publicMints;
    }
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

    /**
     * @dev Emitted upon a mint.
     * @param to          The address to mint to.
     * @param quantity    The number of minted.
     * @param _firstMintedTokenId The first token ID minted.
     */
    event Minted(address to, uint256 quantity, uint256 _firstMintedTokenId);

    /**
     * @dev Emitted when the `operatorFilteringEnabled` is set.
     * @param operatorFilteringEnabled_ The boolean value.
     */
    event OperatorFilteringEnablededSet(bool operatorFilteringEnabled_);

    /**
     * @dev Emitted when the `royaltyBPS` is set.
     * @param bps The new royalty, measured in basis points.
     */
    event RoyaltySet(uint16 bps);

    /**
     * @dev Emitted when the metadata is frozen (e.g.: `baseURI` can no longer be changed).
     * @param baseURI        The base URI of the edition.
     * @param contractURI    The contract URI of the edition.
     */
    event MetadataFrozen(string baseURI, string contractURI);

    /// @notice Event emitted when the funds are withdrawn from the minting contract
    /// @param withdrawnBy address that issued the withdraw
    /// @param withdrawnTo address that the funds were withdrawn to
    /// @param amount amount that was withdrawn
    /// @param feeRecipient user getting withdraw fee (if any)
    /// @param feeAmount amount of the fee getting sent (if any)
    event FundsWithdrawn(
        address indexed withdrawnBy,
        address indexed withdrawnTo,
        uint256 amount,
        address feeRecipient,
        uint256 feeAmount
    );

    /// @notice Event emitted for each sale
    /// @param to address sale was made to
    /// @param quantity quantity of the minted nfts
    /// @param pricePerToken price for each token
    /// @param firstPurchasedTokenId first purchased token ID (to get range add to quantity for max)
    event Sale(
        address indexed to,
        uint256 indexed quantity,
        uint256 indexed pricePerToken,
        uint256 firstPurchasedTokenId
    );

    /// @notice Sales configuration has been changed
    /// @dev To access new sales configuration, use getter function.
    /// @param changedBy Changed by user
    event SalesConfigChanged(address indexed changedBy);

    event ContractURISet(string indexed _contractURI);

    event BaseURISet(string indexed _baseURI);

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev No addresses to airdrop.
     */
    error NoAddressesToAirdrop();

    // Sale/Purchase errors
    /// @notice Sale is inactive
    error Sale_Inactive();
    /// @notice Presale is inactive
    error Presale_Inactive();
    /// @notice Presale merkle root is invalid
    error Presale_MerkleNotApproved();
    /// @notice Wrong price for purchase
    error Purchase_WrongPrice(uint256 correctPrice);
    /// @notice NFT sold out
    error Mint_SoldOut();
    /// @notice Too many purchase for address
    error Purchase_TooManyForAddress();
    /// @notice Too many presale for address
    error Presale_TooManyForAddress();

    error WithdrawFundsSendFailure();

    /**
     * @dev The given `InvalidPayoutAddress` address is invalid.
     */
    error InvalidPayoutAddress();

    /**
     * @dev Emitted when the `payoutAddress` is set.
     * @param payoutAddress The address of the funding recipient.
     */
    event PayoutAddressSet(address payoutAddress);

    /**
     * @dev The given `royaltyBPS` is invalid.
     */
    error InvalidRoyaltyBPS();

    /**
     * @dev The edition's metadata is frozen (e.g.: `baseURI` can no longer be changed).
     */
    error MetadataIsFrozen();

    /**
     * @dev The requested quantity exceeds the edition's remaining mintable token quantity.
     * @param available The number of tokens remaining available for mint.
     */
    error ExceedsEditionAvailableSupply(uint32 available);

    /**
     * @dev The mint `quantity` cannot exceed `ADDRESS_BATCH_MINT_LIMIT` tokens.
     */
    error ExceedsAddressBatchMintLimit();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_,
        address payoutAddress_,
        uint16 royaltyBPS_,
        SalesConfiguration memory _salesconfig,
        uint32 editionMaxMintable_,
        uint8 flags_,
        IConsoleFeeManager consoleFeeManager_
    ) external;

    function payAndMint(uint256 quantity)
        external
        payable
        returns (uint256 _firstMintedTokenId);

    function adminMint(address to, uint256 quantity)
        external
        payable
        returns (uint256 _firstMintedTokenId);

    function airdropAdminMint(address[] calldata _to, uint256 _quantity)
        external
        returns (uint256 _firstMintedTokenId);

    /** 
        =============================================================
                        PRESALE FUNCTIONS
        =============================================================
    */

    function purchasePresale(
        uint256 quantity,
        uint256 maxQuantity,
        uint256 pricePerToken,
        bytes32[] calldata merkleProof
    ) external payable returns (uint256);

    function setSaleConfiguration(
        uint104 publicSalePrice,
        uint32 maxSalePurchasePerAddress,
        uint64 publicSaleStart,
        uint64 publicSaleEnd,
        uint64 presaleStart,
        uint64 presaleEnd,
        bytes32 presaleMerkleRoot
    ) external;

    function withdrawETH() external;

    // function withdrawERC20(address[] calldata tokens) external;

    /** 
        =============================================================
                         ADMIN FUNCTIONS
        =============================================================
    */

    function reveal(string calldata baseURI_) external;

    function updatePreRevealContent(string memory baseURI_) external;

    function freezeMetadata() external;

    function setRoyalty(uint16 royaltyBPS_) external;

    function setPayoutAddress(address _payoutAddress) external;

    function setApprovalForAll(address operator, bool approved) external;

    function setBaseURI(string memory baseURI) external;

    function setContractURI(string memory contractURI) external;
    
}
