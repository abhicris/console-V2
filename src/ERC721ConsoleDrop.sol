// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ERC721AUpgradeable, ERC721AStorage} from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import {IERC721AUpgradeable} from "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
import {OperatorFilterer} from "operator-filter-registry/OperatorFilterer.sol";
import {IERC2981Upgradeable, IERC165Upgradeable} from "openzeppelin-contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import {MerkleProofUpgradeable} from "openzeppelin-contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LibString} from "solady/utils/LibString.sol";

// import { MintRandomnessLib } from "./utils/MintRandomnessLib.sol";

import {IERC721ConsoleDrop} from "./interfaces/IERC721ConsoleDrop.sol";
import {IConsoleFeeManager} from "./interfaces/IConsoleFeeManager.sol";

/**
 * @title ERC721DropConsole
 * @notice NFT Implementation cotract for console.createprotocol.org
 * @dev For drops: assumes 1. linear mint order, 2. max number of mints needs to be less than max_uint64
 *       (if you have more than 18 quintillion linear mints you should probably not be using this contract)
 * @author https://github.com/chirag-bgh
 */

contract ERC721DropConsole is
    ERC721AUpgradeable,
    IERC721ConsoleDrop,
    OwnableRoles,
    ReentrancyGuard,
    OperatorFilterer
{
    /**
     *  @dev Access control roles
     */
    uint256 public constant MINTER_ROLE = _ROLE_1;

    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /**
     * @dev This is the max mint batch size for the optimized ERC721A mint contract
     *      See: https://chiru-labs.github.io/ERC721A/#/tips?id=batch-size
     */
    uint256 public constant ADDRESS_BATCH_MINT_LIMIT = 255;

    /**
     * @dev The upper bound of the max mintable quantity for the edition.
     */
    uint32 public editionMaxMintable;

    /**
     * @dev Basis points denominator used in fee calculations.
     */
    uint16 internal constant _MAX_BPS = 10_000;

    /**
     * @dev The interface ID for EIP-2981 (royaltyInfo)
     */
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

    bytes4 private constant _INTERFACE_ID_SOUND_EDITION_V1 = 0x50899e54;

    /**
     * @dev The boolean flag on whether the metadata is frozen.
     */
    uint8 public constant METADATA_IS_FROZEN_FLAG = 1 << 0;

    /**
     * @dev The boolean flag on whether the `mintRandomness` is enabled.
     */
    uint8 public constant MINT_RANDOMNESS_ENABLED_FLAG = 1 << 1;

    /**
     * @dev The boolean flag on whether OpenSea operator filtering is enabled.
     */
    uint8 public constant OPERATOR_FILTERING_ENABLED_FLAG = 1 << 2;

    /**
     * @dev The boolean flag on whether the collection is revealed.
     */
    uint8 public constant REVEALED_FLAG = 1 << 3;

    /**
     * @dev The value for `name` and `symbol` if their combined
     *      length is (32 - 2) bytes. We need 2 bytes for their lengths.
     */
    bytes32 private _shortNameAndSymbol;

    /**
     * @notice The base URI used for all NFTs in this collection.
     * @dev The `<tokenId>.json` is appended to this to obtain an NFT's `tokenURI`.
     *      e.g. The URI for `tokenId`: "1" with `baseURI`: "ipfs://foo/" is "ipfs://foo/1.json".
     * @return The base URI used by this collection.
     */
    string public baseURIStorage;

    /**
     * @dev contract URI for contract metadata.
     */
    string public contractURIStorage;

    /**
     * @dev ETH and ERC20 Withdrawals
     */
    address public payoutAddress;

    /**
     * @dev
     */
    IConsoleFeeManager public consoleFeeManager;

    /**
     * @dev The randomness based on latest block hash, which is stored upon each mint
     *      unless `randomnessLockedAfterMinted` or `randomnessLockedTimestamp` have been surpassed.
     *      Used for game mechanics like the Sound Golden Egg.
     */
    uint72 private _mintRandomness;

    /**
     * @dev The royalty fee in basis points.
     */
    uint16 public royaltyBPS;

    /**
     * @dev Packed boolean flags.
     */
    uint8 private _flags;

    /// @notice Configuration for NFT minting contract storage
    IERC721ConsoleDrop.Configuration public config;

    /// @notice Sales configuration
    IERC721ConsoleDrop.SalesConfiguration public salesConfig;

    /// @dev Mapping for presale mint counts by address to allow public mint limit
    mapping(address => uint256) public presaleMintsByAddress;

    bool public isRevealed;

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    /**
     * @dev Initializes the contract.
     * @param name_                    Name of the collection.
     * @param symbol_                  Symbol of the collection.
     * @param baseURI_                 Base URI.
     * @param contractURI_             Contract URI for OpenSea storefront.
     * @param payoutAddress_           Address that receives primary and secondary royalties.
     * @param royaltyBPS_              Royalty amount in bps (basis points).
     * @param flags_                   The bitwise OR result of the initialization flags.
     *                                 See: {METADATA_IS_FROZEN_FLAG}
     *                                 See: {MINT_RANDOMNESS_ENABLED_FLAG}
     */
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
    ) external onlyValidRoyaltyBPS(royaltyBPS_) {
        // Prevent double initialization.
        // We can "cheat" here and avoid the initializer modifer to save a SSTORE,
        // since the `_nextTokenId()` is defined to always return 1.
        if (_nextTokenId() != 0) revert Unauthorized();

        if (payoutAddress_ == address(0)) revert InvalidPayoutAddress();

        _initializeNameAndSymbol(name_, symbol_);
        ERC721AStorage.layout()._currentIndex = _startTokenId();

        _initializeOwner(msg.sender);

        baseURIStorage = baseURI_;
        contractURIStorage = contractURI_;
        payoutAddress = payoutAddress_;
        salesConfig = _salesconfig;
        _flags = flags_;
        royaltyBPS = royaltyBPS_;
        consoleFeeManager = consoleFeeManager_;
        editionMaxMintable = editionMaxMintable_;

        // emit ConsoleDropInitialized(
        //     address(this),
        //     name_,
        //     symbol_,
        //     metadataModule_,
        //     baseURI_,
        //     contractURI_,
        //     fundingRecipient_,
        //     royaltyBPS_,
        //     editionMaxMintableLower_,
        //     editionMaxMintableUpper_,
        //     editionCutoffTime_,
        //     flags_
        // );

        if (flags_ & OPERATOR_FILTERING_ENABLED_FLAG != 0) {
            _registerForOperatorFiltering();
        }
    }

    /** 
        =============================================================
                         PUBLIC AND ADMIN MINT FUNCTIONS
        =============================================================
    */

    /**
     * @dev Mints `quantity` tokens to addrress `to`
     *      Each token will be assigned a token ID that is consecutively increasing.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract, or have either the
     *   `ADMIN_ROLE`, `MINTER_ROLE`, which can be granted via {grantRole}.
     *   Multiple minters, such as different minter contracts,
     *   can be authorized simultaneously.
     * @param quantity Number of tokens to mint.
     * @return _firstMintedTokenId The first token ID minted.
     */
    function payAndMint(uint256 quantity)
        external
        payable
        requireWithinAddressBatchMintLimit(quantity)
        requireMintable(quantity)
        returns (uint256 _firstMintedTokenId)
    {
        uint256 mintPrice = salesConfig.publicSalePrice;

        if (msg.value != mintPrice * quantity) {
            revert Purchase_WrongPrice(mintPrice * quantity);
        }

        // If max purchase per address == 0 there is no limit.
        // Any other number, the per address mint limit is that.
        if (
            salesConfig.maxSalePurchasePerAddress != 0 &&
            _numberMinted(msg.sender) +
                quantity -
                presaleMintsByAddress[msg.sender] >
            salesConfig.maxSalePurchasePerAddress
        ) {
            revert Purchase_TooManyForAddress();
        }

        _firstMintedTokenId = _nextTokenId();
        _mint(msg.sender, quantity);

        emit Minted(msg.sender, quantity, _firstMintedTokenId);
    }

    function adminMint(address to, uint256 quantity)
        external
        payable
        onlyRolesOrOwner(ADMIN_ROLE)
        requireMintable(quantity)
        returns (uint256 _firstMintedTokenId)
    {
        _firstMintedTokenId = _nextTokenId();
        // Mint the tokens. Will revert if `quantity` is zero.
        _mint(to, quantity);

        emit Minted(to, quantity, _firstMintedTokenId);
    }

    function airdropAdminMint(address[] calldata _to, uint256 _quantity)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        returns (uint256 _firstMintedTokenId)
    {
        if (_to.length == 0) revert NoAddressesToAirdrop();
        // lastMintedTokenId would cost sub op cost
        _firstMintedTokenId = _nextTokenId();
        unchecked {
            uint256 toLength = _to.length;
            for (uint256 i; i != toLength; ++i) {
                _mint(_to[i], _quantity);
            }
        }

        emit Airdropped(_to, _quantity, _firstMintedTokenId);
    }

    /** 
        =============================================================
                        PRESALE FUNCTIONS
        =============================================================
    */

    /**
      @notice Merkle-tree based presale purchase function
      @param quantity quantity to purchase
      @param maxQuantity max quantity that can be purchased via merkle proof #
      @param pricePerToken price that each token is purchased at
      @param merkleProof proof for presale mint
    */
    function purchasePresale(
        uint256 quantity,
        uint256 maxQuantity,
        uint256 pricePerToken,
        bytes32[] calldata merkleProof
    )
        external
        payable
        nonReentrant
        requireMintable(quantity)
        onlyPresaleActive
        returns (uint256)
    {
        if (
            !MerkleProofUpgradeable.verify(
                merkleProof,
                salesConfig.presaleMerkleRoot,
                keccak256(
                    // address, uint256, uint256
                    abi.encode(msg.sender, maxQuantity, pricePerToken)
                )
            )
        ) {
            revert Presale_MerkleNotApproved();
        }

        if (msg.value != pricePerToken * quantity) {
            revert Purchase_WrongPrice(pricePerToken * quantity);
        }

        presaleMintsByAddress[msg.sender] += quantity;
        if (presaleMintsByAddress[msg.sender] > maxQuantity) {
            revert Presale_TooManyForAddress();
        }

        _mint(msg.sender, quantity);
        uint256 firstMintedTokenId = _nextTokenId();

        emit IERC721ConsoleDrop.Sale({
            to: msg.sender,
            quantity: quantity,
            pricePerToken: pricePerToken,
            firstPurchasedTokenId: firstMintedTokenId
        });

        return firstMintedTokenId;
    }

    /// @dev This sets the sales configuration
    /// @param publicSalePrice New public sale price
    /// @param maxSalePurchasePerAddress Max # of purchases (public) per address allowed
    /// @param publicSaleStart unix timestamp when the public sale starts
    /// @param publicSaleEnd unix timestamp when the public sale ends (set to 0 to disable)
    /// @param presaleStart unix timestamp when the presale starts
    /// @param presaleEnd unix timestamp when the presale ends
    /// @param presaleMerkleRoot merkle root for the presale information
    function setSaleConfiguration(
        uint104 publicSalePrice,
        uint32 maxSalePurchasePerAddress,
        uint64 publicSaleStart,
        uint64 publicSaleEnd,
        uint64 presaleStart,
        uint64 presaleEnd,
        bytes32 presaleMerkleRoot
    ) external onlyRolesOrOwner(ADMIN_ROLE) {
        salesConfig.publicSalePrice = publicSalePrice;
        salesConfig.maxSalePurchasePerAddress = maxSalePurchasePerAddress;
        salesConfig.publicSaleStart = publicSaleStart;
        salesConfig.publicSaleEnd = publicSaleEnd;
        salesConfig.presaleStart = presaleStart;
        salesConfig.presaleEnd = presaleEnd;
        salesConfig.presaleMerkleRoot = presaleMerkleRoot;

        emit SalesConfigChanged(msg.sender);
    }

    /** 
        =============================================================
                         PUBLIC/EXTERNAL FUNCTIONS
        =============================================================
    */

    /**
     * @dev Withdraws collected ETH royalties to the payout address and console.
     */
    function withdrawETH() external nonReentrant {
        uint256 fundsRemaining = address(this).balance;
        address feeRecipient = consoleFeeManager.getConsoleFeeManager();
        uint256 consoleFee = consoleFeeManager.platformFee(
            uint128(fundsRemaining)
        );

        // Payout console fee
        if (consoleFee > 0) {
            (bool successFee, ) = feeRecipient.call{
                value: consoleFee,
                gas: 210_000
            }("");
            if (!successFee) {
                revert WithdrawFundsSendFailure();
            }
            fundsRemaining -= consoleFee;
        }

        // Payout recipient
        (bool successFunds, ) = payoutAddress.call{
            value: fundsRemaining,
            gas: 210_000
        }("");
        if (!successFunds) {
            revert WithdrawFundsSendFailure();
        }

        emit FundsWithdrawn(
            msg.sender,
            payoutAddress,
            fundsRemaining,
            feeRecipient,
            consoleFee
        );
    }

    /**
     * @dev Withdraws collected ERC20 royalties to the fundingRecipient.
     * @param tokens array of ERC20 tokens to withdraw
     */
    // function withdrawERC20(address[] calldata tokens) external {

    //     // Payout console fee

    //     // Payout recipient
    //     unchecked {
    //         uint256 n = tokens.length;
    //         uint256[] memory amounts = new uint256[](n);
    //         for (uint256 i; i != n; ++i) {
    //             uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
    //             SafeTransferLib.safeTransfer(tokens[i], payoutAddress, amount);
    //             amounts[i] = amount;
    //         }
    //         emit ERC20Withdrawn(fundingRecipient, tokens, amounts, msg.sender);
    //     }
    // }

    /** 
        =============================================================
                         ADMIN FUNCTIONS
        =============================================================
    */

    /**
     * @notice Allows a collection admin to reveal the collection's final content.
     * @dev Once revealed, the collection's content is immutable.
     * Use `updatePreRevealContent` to update content while unrevealed.
     * @param baseURI_ The base URI of the final content for this collection.
     */
    function reveal(string calldata baseURI_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        require(!isRevealed);
        isRevealed = true;
        // Set the new base URI.
        baseURIStorage = baseURI_;
        emit URIUpdated(baseURI_, true);
    }

    /**
     * @notice Allows a collection admin to update the pre-reveal content.
     * @dev Use `reveal` to reveal the final content for this collection.
     * @param baseURI_ The base URI of the pre-reveal content.
     */
    function updatePreRevealContent(string memory baseURI_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        require(!isRevealed);
        baseURIStorage = baseURI_;
        emit URIUpdated(baseURI_, false);
    }

    function setContractURI(string memory contractURI_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        onlyMetadataNotFrozen
    {
        contractURIStorage = contractURI_;

        emit ContractURISet(contractURI_);
    }

    function setBaseURI(string memory contractURI_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        onlyMetadataNotFrozen
    {
        baseURIStorage = contractURI_;

        emit BaseURISet(contractURI_);
    }

    /**
     * @dev frezzes metadata
     */
    function freezeMetadata()
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        onlyMetadataNotFrozen
    {
        _flags |= METADATA_IS_FROZEN_FLAG;
        emit MetadataFrozen(baseURI(), contractURI());
    }

    /**
     * @dev sets royalty
     */
    function setRoyalty(uint16 royaltyBPS_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        onlyValidRoyaltyBPS(royaltyBPS_)
    {
        royaltyBPS = royaltyBPS_;
        emit RoyaltySet(royaltyBPS_);
    }

    function setPayoutAddress(address _payoutAddress)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        if (_payoutAddress == address(0)) revert InvalidPayoutAddress();
        payoutAddress = _payoutAddress;
        emit PayoutAddressSet(payoutAddress);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function setApprovalForAll(address operator, bool approved)
        public
        override(IERC721ConsoleDrop, ERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.setApprovalForAll(operator, approved);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function approve(address operator, uint256 tokenId)
        public
        payable
        override(ERC721AUpgradeable)
        onlyAllowedOperatorApproval(operator)
    {
        super.approve(operator, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721AUpgradeable) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721AUpgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public payable override(ERC721AUpgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     * @dev params for batch transfer
     */

    struct batchTransferParams {
        address recipient;
        uint256[] tokenIds;
    }

    /**
     * @dev Batch transfer minted nfts to a single address
     */
    function safeBatchTransfer(batchTransferParams memory params) internal {
        uint256 length = params.tokenIds.length;
        for (uint256 i; i < length; ) {
            uint256 _tokenId = params.tokenIds[i];
            safeTransferFrom(owner(), params.recipient, _tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Batch transfer to multiple nft
     */
    function safeBatchTransferPublic(batchTransferParams[] memory params)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        uint256 length = params.length;
        for (uint256 i; i < length; ) {
            safeBatchTransfer(params[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setOwner(address newOwner) public onlyOwnerOrRoles(ADMIN_ROLE) {
        // import ownable library
        _setOwner(newOwner);
    }

    // function setMintRandomnessEnabled(bool mintRandomnessEnabled_) external onlyRolesOrOwner(ADMIN_ROLE) {
    //     if (_totalMinted() != 0) revert MintsAlreadyExist();

    //     if (mintRandomnessEnabled() != mintRandomnessEnabled_) {
    //         _flags ^= MINT_RANDOMNESS_ENABLED_FLAG;
    //     }

    //     emit MintRandomnessEnabledSet(mintRandomnessEnabled_);
    // }

    function setOperatorFilteringEnabled(bool operatorFilteringEnabled_)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
    {
        if (operatorFilteringEnabled() != operatorFilteringEnabled_) {
            _flags ^= OPERATOR_FILTERING_ENABLED_FLAG;
            if (operatorFilteringEnabled_) {
                _registerForOperatorFiltering();
            }
        }

        emit OperatorFilteringEnablededSet(operatorFilteringEnabled_);
    }

    /** 
        =============================================================
                          PUBLIC/EXTERNAL VIEW FUNCTIONS
        =============================================================
    */

    function owner() public view override returns (address) {
        return super.owner();
    }

    // function mintRandomness() public view returns (uint256) {

    //     if (mintConcluded() && mintRandomnessEnabled()) {
    //         return uint256(keccak256(abi.encode(_mintRandomness, address(this))));
    //     }
    //     return 0;
    // }

    // function mintRandomnessEnabled() public view returns (bool) {
    //     return _flags & MINT_RANDOMNESS_ENABLED_FLAG != 0;
    // }

    function _editionMaxMintable() public view returns (uint32) {
        return editionMaxMintable;
    }

    function operatorFilteringEnabled() public view returns (bool) {
        return _operatorFilteringEnabled();
    }

    function mintConcluded() public view returns (bool) {
        return _totalMinted() == _editionMaxMintable();
    }

    function nextTokenId() public view returns (uint256) {
        return _nextTokenId();
    }

    function numberMinted(address owner) external view returns (uint256) {
        return _numberMinted(owner);
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721AUpgradeable)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI_ = baseURI();
        return
            bytes(baseURI_).length != 0
                ? string.concat(baseURI_, _toString(tokenId))
                : "";
    }

    /**
     * @dev Informs other contracts which interfaces this contract supports.
     *      Required by https://eips.ethereum.org/EIPS/eip-165
     * @param interfaceId The interface id to check.
     * @return Whether the `interfaceId` is supported.
     */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721AUpgradeable)
        returns (bool)
    {
        return
            interfaceId == _INTERFACE_ID_SOUND_EDITION_V1 ||
            interfaceId == type(IERC721ConsoleDrop).interfaceId ||
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            interfaceId == _INTERFACE_ID_ERC2981 ||
            interfaceId == this.supportsInterface.selector;
    }

    function royaltyInfo(
        uint256, // tokenId
        uint256 salePrice
    ) external view returns (address fundingRecipient_, uint256 royaltyAmount) {
        fundingRecipient_ = payoutAddress;
        royaltyAmount = (salePrice * royaltyBPS) / _MAX_BPS;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function name()
        public
        view
        override(ERC721AUpgradeable)
        returns (string memory)
    {
        (string memory name_, ) = _loadNameAndSymbol();
        return name_;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function symbol()
        public
        view
        override(ERC721AUpgradeable)
        returns (string memory)
    {
        (, string memory symbol_) = _loadNameAndSymbol();
        return symbol_;
    }

    /**
     * @dev returns baseuri
     */
    function baseURI() public view returns (string memory) {
        return baseURIStorage;
    }

    /**
     * @dev returns contract uri
     */
    function contractURI() public view returns (string memory) {
        return contractURIStorage;
    }

    // =============================================================
    //                  INTERNAL / PRIVATE HELPERS
    // =============================================================

    /**
     * @dev Overrides the `_startTokenId` function from ERC721A
     *      to start at token id `1`.
     *
     *      This is to avoid future possible problems since `0` is usually
     *      used to signal values that have not been set or have been removed.
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function _presaleActive() internal view returns (bool) {
        return
            salesConfig.presaleStart <= block.timestamp &&
            salesConfig.presaleEnd > block.timestamp;
    }

    /**
     * @dev Presale Active
     */
    modifier onlyPresaleActive() {
        if (!_presaleActive()) {
            revert Presale_Inactive();
        }
        _;
    }

    /**
     * @dev Ensures the royalty basis points is a valid value.
     * @param bps The royalty BPS.
     */
    modifier onlyValidRoyaltyBPS(uint16 bps) {
        if (bps > _MAX_BPS) revert InvalidRoyaltyBPS();
        _;
    }

    /**
     * @dev Reverts if the metadata is frozen.
     */
    modifier onlyMetadataNotFrozen() {
        // Inlined to save gas.
        if (_flags & METADATA_IS_FROZEN_FLAG != 0) revert MetadataIsFrozen();
        _;
    }

    /**
     * @dev Ensures that `totalQuantity` can be minted.
     * @param totalQuantity The total number of tokens to mint.
     */
    modifier requireMintable(uint256 totalQuantity) {
        unchecked {
            uint256 currentTotalMinted = totalMinted();
            uint256 currentEditionMaxMintable = _editionMaxMintable();
            // Check if there are enough tokens to mint.
            // We use version v4.2+ of ERC721A, which `_mint` will revert with out-of-gas
            // error via a loop if `totalQuantity` is large enough to cause an overflow in uint256.
            if (
                currentTotalMinted + totalQuantity > currentEditionMaxMintable
            ) {
                // Won't underflow.
                //
                // `currentTotalMinted`, which is `_totalMinted()`,
                // will return either `editionMaxMintableUpper`
                // or `max(editionMaxMintableLower, _totalMinted())`.
                //
                // We have the following invariants:
                // - `editionMaxMintableUpper >= _totalMinted()`
                // - `max(editionMaxMintableLower, _totalMinted()) >= _totalMinted()`
                uint256 available = currentEditionMaxMintable -
                    currentTotalMinted;
                revert ExceedsEditionAvailableSupply(uint32(available));
            }
        }
        _;
    }

    /**
     * @dev Ensures that the `quantity` does not exceed `ADDRESS_BATCH_MINT_LIMIT`.
     * @param quantity The number of tokens minted per address.
     */
    modifier requireWithinAddressBatchMintLimit(uint256 quantity) {
        if (quantity > ADDRESS_BATCH_MINT_LIMIT)
            revert ExceedsAddressBatchMintLimit();
        _;
    }

    // /**
    //  * @dev Updates the mint randomness.
    //  */
    // modifier updatesMintRandomness() {
    //     if (mintRandomnessEnabled() && !mintConcluded()) {
    //         uint256 randomness = _mintRandomness;
    //         uint256 newRandomness = MintRandomnessLib.nextMintRandomness(
    //             randomness,
    //             _totalMinted(),
    //             editionMaxMintable()
    //         );
    //         if (newRandomness != randomness) {
    //             _mintRandomness = uint72(newRandomness);
    //         }
    //     }
    //     _;
    // }

    /**
     * @dev Helper function for initializing the name and symbol,
     *      packing them into a single word if possible.
     * @param name_   Name of the collection.
     * @param symbol_ Symbol of the collection.
     */
    function _initializeNameAndSymbol(
        string memory name_,
        string memory symbol_
    ) internal {
        // Overflow impossible since max block gas limit bounds the length of the strings.
        unchecked {
            // Returns `bytes32(0)` if the strings are too long to be packed into a single word.
            bytes32 packed = LibString.packTwo(name_, symbol_);
            // If we cannot pack both strings into a single 32-byte word, store separately.
            // We need 2 bytes to store their lengths.
            if (packed == bytes32(0)) {
                ERC721AStorage.layout()._name = name_;
                ERC721AStorage.layout()._symbol = symbol_;
                return;
            }
            // Otherwise, pack them and store them into a single word.
            _shortNameAndSymbol = packed;
        }
    }

    /**
     * @dev Helper function for retrieving the name and symbol,
     *      unpacking them from a single word in storage if previously packed.
     * @return name_   Name of the collection.
     * @return symbol_ Symbol of the collection.
     */
    function _loadNameAndSymbol()
        internal
        view
        returns (string memory name_, string memory symbol_)
    {
        // Overflow impossible since max block gas limit bounds the length of the strings.
        unchecked {
            bytes32 packed = _shortNameAndSymbol;
            // If the strings have been previously packed.
            if (packed != bytes32(0)) {
                (name_, symbol_) = LibString.unpackTwo(packed);
            } else {
                // Otherwise, load them from their separate variables.
                name_ = ERC721AStorage.layout()._name;
                symbol_ = ERC721AStorage.layout()._symbol;
            }
        }
    }
}
