// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { ERC721AUpgradeable, ERC721AStorage } from "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import { IERC721AUpgradeable } from "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
import { OperatorFilterer } from "operator-filter-registry/OperatorFilterer.sol";
import { IERC2981Upgradeable } from "openzeppelin-contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { MintRandomnessLib } from "./utils/MintRandomnessLib.sol";
import { IERC721ConsoleDrop } from "./interfaces/IERC721ConsoleDrop.sol";



/// @title ERC721DropConsole
/// @author https://github.com/chirag-bgh
/// @notice NFT Implementation contract for console.createprotocol.org


contract ERC721DropConsole is IERC721ConsoleDrop, OwnableRoles {

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
     * @dev Basis points denominator used in fee calculations.
     */
    uint16 internal constant _MAX_BPS = 10_000;

    /**
     * @dev The interface ID for EIP-2981 (royaltyInfo)
     */
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;

     /**
     * @dev The destination for ETH and ERC20 withdrawals.
     */
    address public payoutAddress;


    /**
     * @dev Operator filter registry
     */
    IOperatorFilterRegistry immutable operatorFilterRegistry =
        IOperatorFilterRegistry(0x000000000000AAeB6D7670E522A718067333cd4E);

    /**
     * @notice Whether the collection is revealed or not.
     */
    bool public isRevealed;

    /**
     * @notice The base URI used for all NFTs in this collection.
     * @dev The `<tokenId>.json` is appended to this to obtain an NFT's `tokenURI`.
     *      e.g. The URI for `tokenId`: "1" with `baseURI`: "ipfs://foo/" is "ipfs://foo/1.json".
     * @return The base URI used by this collection.
     */
    string public baseURI;

    /**
     * @dev contract URI for contract metadata.
     */
    string public contractURI;

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

    /** 
        =============================================================
                         MODIFIERS
        =============================================================
     */

    /**
     * @dev For operator filtering to be toggled on / off.
     */
    function _operatorFilteringEnabled() internal view override returns (bool) {
        return _flags & OPERATOR_FILTERING_ENABLED_FLAG != 0;
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
     * @dev Ensures that `totalQuantity` can be minted.
     * @param totalQuantity The total number of tokens to mint.
     */
    modifier requireMintable(uint256 totalQuantity) {
        unchecked {
            uint256 currentTotalMinted = _totalMinted();
            uint256 currentEditionMaxMintable = editionMaxMintable();
            // Check if there are enough tokens to mint.
            // We use version v4.2+ of ERC721A, which `_mint` will revert with out-of-gas
            // error via a loop if `totalQuantity` is large enough to cause an overflow in uint256.
            if (currentTotalMinted + totalQuantity > currentEditionMaxMintable) {
                // Won't underflow.
                //
                // `currentTotalMinted`, which is `_totalMinted()`,
                // will return either `editionMaxMintableUpper`
                // or `max(editionMaxMintableLower, _totalMinted())`.
                //
                // We have the following invariants:
                // - `editionMaxMintableUpper >= _totalMinted()`
                // - `max(editionMaxMintableLower, _totalMinted()) >= _totalMinted()`
                uint256 available = currentEditionMaxMintable - currentTotalMinted;
                revert ExceedsEditionAvailableSupply(uint32(available));
            }
        }
        _;
    }

    /**
     * @dev Updates the mint randomness.
     */
    modifier updatesMintRandomness() {
        if (mintRandomnessEnabled() && !mintConcluded()) {
            uint256 randomness = _mintRandomness;
            uint256 newRandomness = MintRandomnessLib.nextMintRandomness(
                randomness,
                _totalMinted(),
                editionMaxMintable()
            );
            if (newRandomness != randomness) {
                _mintRandomness = uint72(newRandomness);
            }
        }
        _;
    }


    function initialize(
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_,
        address payoutAddress_,
        uint16 royaltyBPS_,
        uint32 editionMaxMintableLower_,
        uint32 editionMaxMintableUpper_,
        uint32 editionCutoffTime_,
        uint8 flags_
    ) external onlyValidRoyaltyBPS(royaltyBPS_) {
        // Prevent double initialization.
        // We can "cheat" here and avoid the initializer modifer to save a SSTORE,
        // since the `_nextTokenId()` is defined to always return 1.
        if (_nextTokenId() != 0) revert Unauthorized();

        if (fundingRecipient_ == address(0)) revert InvalidFundingRecipient();

        if (editionMaxMintableLower_ > editionMaxMintableUpper_) revert InvalidEditionMaxMintableRange();

        _initializeNameAndSymbol(name_, symbol_);
        ERC721AStorage.layout()._currentIndex = _startTokenId();

        _initializeOwner(msg.sender);

        _baseURIStorage.initialize(baseURI_);
        _contractURIStorage.initialize(contractURI_);

        fundingRecipient = fundingRecipient_;
        editionMaxMintableUpper = editionMaxMintableUpper_;
        editionMaxMintableLower = editionMaxMintableLower_;
        editionCutoffTime = editionCutoffTime_;

        _flags = flags_;

        metadataModule = metadataModule_;
        royaltyBPS = royaltyBPS_;

        emit SoundEditionInitialized(
            address(this),
            name_,
            symbol_,
            metadataModule_,
            baseURI_,
            contractURI_,
            fundingRecipient_,
            royaltyBPS_,
            editionMaxMintableLower_,
            editionMaxMintableUpper_,
            editionCutoffTime_,
            flags_
        );

        if (flags_ & OPERATOR_FILTERING_ENABLED_FLAG != 0) {
            _registerForOperatorFiltering();
        }
    }

    

    /** 
        =============================================================
                         PUBLIC MINT FUNCTIONS
        =============================================================
    */

    /**
     * @notice function to mint NFTs
     * @dev
     * @param qu
     * 
     */
    function payAndMint(uint256 _quantity)
        external
        payable
        requireWithinAddressBatchMintLimit(_quantity)
        requireMintable(quantity)
        updatesMintRandomness
        returns (uint256 _firstMintedTokenId)
    {

        uint256 mintPrice = publicDrop.mintPrice;
         // Validate payment is correct for number minted.
        _checkCorrectPayment(quantity, mintPrice);
        // Check that the minter is allowed to mint the desired quantity.
        _checkMintQuantity(
            nftContract,
            minter,
            quantity,
            publicDrop.maxTotalMintableByWallet,
            _UNLIMITED_MAX_TOKEN_SUPPLY_FOR_STAGE
        );

        _firstMintedTokenId = _nextTokenId();
        _mint(msg.sender, quantity);

        emit Minted(to, quantity, _firstMintedTokenId);
    }

    /** 
        =============================================================
                         ADMIN MINT FUNCTIONS
        =============================================================
    */

    // checkout batchminting in 8 batches

    function airdropAdminMint(address[] calldata _to, uint256 _quantity)
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        returns (uint256 _firstMintedTokenId)
    {
        if (to.length == 0) revert NoAddressesToAirdrop();
        // lastMintedTokenId would cost sub op cost
         _firstMintedTokenId = _nextTokenId();
        unchecked {
            uint256 toLength = _to.length;
            for (uint256 i; i != toLength; ++i) {
                _mint(to[i], quantity);
            }
        }
       
        // assembly {
        //     for { let i := 0 } lt(i, 0x100) { i := add(i, 0x20) } {
        //     }
        // }

        emit Airdropped(to, quantity, _firstMintedTokenId);
    
    }

    /**
     * @notice Free mints by admin
     * @param _recipient 
     * @param _quantitiy
     */

    function adminMint(address _recipient, uint256 _quantity) 
        external
        onlyRolesOrOwner(ADMIN_ROLE)
        requireMintable(quantity)
        returns (uint256 _firstMintedTokenId) 
    {
        _firstMintedTokenId = _nextTokenId();
        _mint(to, quantity);

        emit Minted(to, quantity, _firstMintedTokenId);
    }



    // function purchasePresale(
    //     uint256 quantity,
    //     uint256 maxQuantity,
    //     uint256 pricePerToken,
    //     bytes32[] calldata merkleProof
    // )
    //     external
    //     payable
    //     nonReentrant
    //     canMintTokens(quantity)
    //     onlyPresaleActive
    //     returns (uint256)
    // {


    /** 
        =============================================================
                         CHECK FUNCTIONS
        =============================================================
    */


    /**
     * @notice Revert if the payment is not the quantity times the mint price.
     *
     * @param quantity  The number of tokens to mint.
     * @param mintPrice The mint price per token.
     */
    function _checkCorrectPayment(uint256 quantity, uint256 mintPrice)
        internal
        view
    {
        // Revert if the tx's value doesn't match the total cost.
        if (msg.value != quantity * mintPrice) {
            revert IncorrectPayment(msg.value, quantity * mintPrice);
        }
    }

    /**
     * @notice Check that the wallet is allowed to mint the desired quantity.
     *
     * @param nftContract              The nft contract.
     * @param minter                   The mint recipient.
     * @param quantity                 The number of tokens to mint.
     * @param maxTotalMintableByWallet The max allowed mints per wallet.
     * @param maxTokenSupplyForStage   The max token supply for the drop stage.
     */
    function _checkMintQuantity(
        address nftContract,
        address minter,
        uint256 quantity,
        uint256 maxTotalMintableByWallet,
        uint256 maxTokenSupplyForStage
    ) internal view {
        // Mint quantity of zero is not valid.
        if (quantity == 0) {
            revert MintQuantityCannotBeZero();
        }

        // Get the mint stats.
        (
            uint256 minterNumMinted,
            uint256 currentTotalSupply,
            uint256 maxSupply
        ) = INonFungibleSeaDropToken(nftContract).getMintStats(minter);

        // Ensure mint quantity doesn't exceed maxTotalMintableByWallet.
        if (quantity + minterNumMinted > maxTotalMintableByWallet) {
            revert MintQuantityExceedsMaxMintedPerWallet(
                quantity + minterNumMinted,
                maxTotalMintableByWallet
            );
        }

        // Ensure mint quantity doesn't exceed maxSupply.
        if (quantity + currentTotalSupply > maxSupply) {
            revert MintQuantityExceedsMaxSupply(
                quantity + currentTotalSupply,
                maxSupply
            );
        }

        // Ensure mint quantity doesn't exceed maxTokenSupplyForStage.
        if (quantity + currentTotalSupply > maxTokenSupplyForStage) {
            revert MintQuantityExceedsMaxTokenSupplyForStage(
                quantity + currentTotalSupply,
                maxTokenSupplyForStage
            );
        }
    }

    /** 
        =============================================================
                         PUBLIC/EXTERNAL FUNCTIONS
        =============================================================
    */

   /**
     * @inheritdoc ISoundEditionV1_1
     */
    function withdrawETH() external {
        uint256 amount = address(this).balance;

        // Create Protocol Fees

        if (zoraFee > 0) {
            (bool successFee, ) = feeRecipient.call{
                value: zoraFee,
                gas: FUNDS_SEND_GAS_LIMIT
            }("");
            if (!successFee) {
                revert Withdraw_FundsSendFailure();
            }
            funds -= zoraFee;
        }
        // SafeTransferLib.safeTransferETH(fundingRecipient, amount);
        emit ETHWithdrawn(payoutAddress, amount, msg.sender);

    /**
     * @inheritdoc ISoundEditionV1_1
     */
    function withdrawERC20(address[] calldata tokens) external {
        unchecked {
            uint256 n = tokens.length;
            uint256[] memory amounts = new uint256[](n);
            for (uint256 i; i != n; ++i) {
                uint256 amount = IERC20(tokens[i]).balanceOf(address(this));
                SafeTransferLib.safeTransfer(tokens[i], fundingRecipient, amount);
                amounts[i] = amount;
            }
            emit ERC20Withdrawn(fundingRecipient, tokens, amounts, msg.sender);
        }
    }
    
    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function approve(address operator, uint256 tokenId)
        public
        payable
        override(ERC721AUpgradeable, IERC721AUpgradeable)
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
    ) public payable override(ERC721AUpgradeable, IERC721AUpgradeable) onlyAllowedOperator(from) {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public payable override(ERC721AUpgradeable, IERC721AUpgradeable) onlyAllowedOperator(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    /** 
        =============================================================
                          PUBLIC/EXTERNAL VIEW FUNCTIONS
        =============================================================
    */

   function mintRandomness() public view returns (uint256) {
        if (mintConcluded() && mintRandomnessEnabled()) {
            return uint256(keccak256(abi.encode(_mintRandomness, address(this))));
        }
        return 0;
    }

    function editionMaxMintable() public view returns (uint32) {
        if (block.timestamp < editionCutoffTime) {
            return editionMaxMintableUpper;
        } else {
            return uint32(FixedPointMathLib.max(editionMaxMintableLower, _totalMinted()));
        }
    }

    function mintRandomnessEnabled() public view returns (bool) {
        return _flags & MINT_RANDOMNESS_ENABLED_FLAG != 0;
    }

    function operatorFilteringEnabled() public view returns (bool) {
        return _operatorFilteringEnabled();
    }

    function mintConcluded() public view returns (bool) {
        return _totalMinted() == editionMaxMintable();
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
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI_ = baseURI();
        return bytes(baseURI_).length != 0 ? string.concat(baseURI_, _toString(tokenId)) : "";
    }

    /**
     * @inheritdoc ISoundEditionV1_1
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ISoundEditionV1_1, ERC721AUpgradeable, IERC721AUpgradeable)
        returns (bool)
    {
        return
            interfaceId == _INTERFACE_ID_SOUND_EDITION_V1 ||
            interfaceId == type(ISoundEditionV1_1).interfaceId ||
            ERC721AUpgradeable.supportsInterface(interfaceId) ||
            interfaceId == _INTERFACE_ID_ERC2981 ||
            interfaceId == this.supportsInterface.selector;
    }

    /**
     * @inheritdoc IERC2981Upgradeable
     */
    function royaltyInfo(
        uint256, // tokenId
        uint256 salePrice
    ) external view override(IERC2981Upgradeable) returns (address fundingRecipient_, uint256 royaltyAmount) {
        fundingRecipient_ = fundingRecipient;
        royaltyAmount = (salePrice * royaltyBPS) / _MAX_BPS;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function name() public view override(ERC721AUpgradeable, IERC721AUpgradeable) returns (string memory) {
        return name_;
    }

    /**
     * @inheritdoc IERC721AUpgradeable
     */
    function symbol() public view override(ERC721AUpgradeable, IERC721AUpgradeable) returns (string memory) {
        return symbol_;
    }

    /**
     * @inheritdoc ISoundEditionV1_1
     */
    function baseURI() public view returns (string memory) {
        return _baseURIStorage.load();
    }

    /**
     * @inheritdoc ISoundEditionV1_1
     */
    function contractURI() public view returns (string memory) {
        return _contractURIStorage.load();
    }



    /** 
        =============================================================
                         ADMIN FUNCTIONS
        =============================================================
    */

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
    function safeBatchTransfer(
        batchTransferParams memory params
    ) internal {
        uint256 length = params.tokenIds.length;
        IERC721AUpgradeable nftcontract = IERC721AUpgradeable(address.this)
        for (uint256 i; i < length; ) {
            uint256 tokenId = tokenIds[i];
            address owner = erc721Contract.ownerOf(tokenId);
            erc721Contract.safeTransferFrom(owner, params.recipient, tokenId);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Batch transfer to multiple nft
     */
    function safeBatchTransferPublic(
        batchTransferParams[] memory params
    ) external
      onlyRolesOrOwner(ADMIN_ROLE) {
        uint256 length = params.length;
        IERC721AUpgradeable nftcontract = IERC721AUpgradeable(address.this)
        for (uint256 i; i < length; ) {
            safeBatchTransferToSingleWallet(params[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Allows a collection admin to reveal the collection's final content.
     * @dev Once revealed, the collection's content is immutable.
     * Use `updatePreRevealContent` to update content while unrevealed.
     * @param baseURI_ The base URI of the final content for this collection.
     */
    function reveal(string calldata baseURI_) external onlyAdmin validBaseURI(baseURI_) onlyWhileUnrevealed {
        isRevealed = true;

        // Set the new base URI.
        baseURI = baseURI_;
        emit URIUpdated(baseURI_, true);
    }

    /**
     * @notice Allows a collection admin to update the pre-reveal content.
     * @dev Use `reveal` to reveal the final content for this collection.
     * @param baseURI_ The base URI of the pre-reveal content.
     */
    function updatePreRevealContent(string calldata baseURI_)
        external
        validBaseURI(baseURI_)
        onlyWhileUnrevealed
        onlyAdmin
    {
        baseURI = baseURI_;
        emit URIUpdated(baseURI_, false);
    }



    function setOwner(address newOwner) public onlyOwnerOrRoles(ADMIN_ROLE) {
        // import ownable library
        _setOwner(newOwner);
    }

    function setPayoutAddress(address _payoutAddress) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (_payoutAddress == address(0)) revert InvalidFundingRecipient();
        payoutAddress = _payoutAddress;
        emit payoutAddressSet(payoutAddress);
    }

    function setMintRandomnessEnabled(bool mintRandomnessEnabled_) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (_totalMinted() != 0) revert MintsAlreadyExist();

        if (mintRandomnessEnabled() != mintRandomnessEnabled_) {
            _flags ^= MINT_RANDOMNESS_ENABLED_FLAG;
        }

        emit MintRandomnessEnabledSet(mintRandomnessEnabled_);
    }

    function setOperatorFilteringEnabled(bool operatorFilteringEnabled_) external onlyRolesOrOwner(ADMIN_ROLE) {
        if (operatorFilteringEnabled() != operatorFilteringEnabled_) {
            _flags ^= OPERATOR_FILTERING_ENABLED_FLAG;
            if (operatorFilteringEnabled_) {
                _registerForOperatorFiltering();
            }
        }

        emit OperatorFilteringEnablededSet(operatorFilteringEnabled_);
    }

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



   

   



}


