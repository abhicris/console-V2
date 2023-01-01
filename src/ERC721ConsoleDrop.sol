// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "ERC721A-Upgradeable/ERC721AUpgradeable.sol";
import "ERC721A-Upgradeable/IERC721AUpgradeable.sol";
import "ERC721A-Upgradeable/ERC721AStorage.sol";
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
    uint256 public constant minterRole = _ROLE_1;
    uint256 public constant adminRole = _ROLE_0;

    /**
     * @dev This is the max mint batch size for the optimized ERC721A mint contract
     *      See: https://chiru-labs.github.io/ERC721A/#/tips?id=batch-size
     */
    uint256 public constant ADDRESS_BATCH_MINT_LIMIT = 255;

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
                          PUBLIC VIEW FUNCTIONS
        =============================================================
    */

   function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) {
            revert IERC721AUpgradeable.URIQueryForNonexistentToken();
        }

        return config.metadataRenderer.tokenURI(tokenId);
    }

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

    function contractURI() external view returns (string memory) {
        return config.metadataRenderer.contractURI();
    }

    /// @notice Getter for metadataRenderer contract
    function metadataRenderer() external view returns (IMetadataRenderer) {
        return IMetadataRenderer(config.metadataRenderer);
    }

    /** 
        =============================================================
                         ADMIN CONFIG FUNCTIONS
        =============================================================
    */


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

    function setPublicSaleConfig() public onlyOwnerOrRoles(ADMIN_ROLE) {}



   




    /** 
        =============================================================
                         MODIFIERS
        =============================================================
    */



}


