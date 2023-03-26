//SPDX-License-Identifier: MIT
pragma solidity 0.8 .17;

import { ERC721ConsoleDrop,  IERC721ConsoleDrop } from "../src/ERC721ConsoleDrop.sol";
import { DropProxyFactory, IDropProxyFactory } from "../src/DropProxyFactory.sol";
import { ConsoleFeeManager } from "../src/ConsoleFeeManager";
import { IConsoleFeeManager } from "../src/interfaces/IConsoleFeeManager.sol";
import { OwnableRoles } from "solady/auth/OwnableRoles.sol";
import { BN, expectEvent, expectRevert } from ('@openzeppelin/test-helpers');

import "./TestConfig.sol";

contract TestDropProxyFactory is TestConfig {

    event ConsoleDropInitialized(
        address myTokenContractAddress,
        string memory name_,
        string memory symbol_,
        string memory baseURI_,
        string memory contractURI_,
        address payoutAddress_,
        uint16 royaltyBPS_,
        uint32 editionMaxMintable_,
        uint8 flags_,
        IConsoleFeeManager consoleFeeManager
    )

    event Minted(address sender, uint256 quantity, uint256 _firstMintedTokenId);

    uint8 public constant METADATA_IS_FROZEN_FLAG = 1 << 0;
    uint8 public constant MINT_RANDOMNESS_ENABLED_FLAG = 1 << 1;

    // Artist contract creation vars
    address constant payoutAddress_ = address(0x0111111);
    address constant consoleFeeAddress = address(0x0222222);

    string constant NAME = 'MyNFT';
    string constant symbol_ = 'MNT';
    string constant baseURI_ = 'https://example.com/metadata/';
    string constant contractURI_ = 'https://example.com/storefront/';
    
    uint8 constant flags_ = MINT_RANDOMNESS_ENABLED_FLAG;
    uint16 constant platformFeeBPS = 500;
    uint16 constant royaltyBPS_ = 100;
    uint32 constant editionMaxMintable_ = type(uint32).max;
    uint32 maxSalePurchasePerAddress = 10;
    uint64 publicSaleStart = 1;
    uint64 publicSaleEnd = 500;
    uint64 presaleStart = 1;
    uint64 presaleEnd = 500;

    uint104 publicSalePrice = 10;
    
    bytes32 presaleMerkleRoot = 0x0;
    
    ERC721ConsoleDrop myTokenContract = address(0x0);

    SalesConfiguration _salesconfig = setSaleConfiguration(
        publicSalePrice,
        maxSalePurchasePerAddress,
        publicSaleStart,
        publicSaleEnd,
        presaleStart,
        presaleEnd,
        presaleMerkleRoot
    );

    ConsoleFeeManager consoleFeeManager = new ConsoleFeeManager(
        consoleFeeAddress,
        platformFeeBPS
    );

    function beforeEach() public {
        // Deploy a new instance of the PresaleContract before each test
        // myTokenContract = new ERC721ConsoleDrop();
        testInitilisation();
    }

    function testInitilisation() {
        
        assert(address(myTokenContract) == address(0x0), "The myTokenContract address before initialize should be 0x0.");

        myTokenContract.initialize( name_, symbol_, baseURI_, contractURI_, payoutAddress_, royaltyBPS_, _salesconfig,editionMaxMintable_, flags_, consoleFeeManager );

        myTokenContract = new ERC721ConsoleDrop();

        emit ConsoleDropInitialized( address(myTokenContract), name_, symbol_, baseURI_, contractURI_, payoutAddress_, royaltyBPS_, editionMaxMintableLower_, editionMaxMintableUpper_, editionCutoffTime_, flags_, consoleFeeManager );

        assert(address(myTokenContract) != address(0x0), "The myTokenContract address post initialize should not be 0x0.");

    }

    /// test payAndMint(uint256 quantity)
    function testPayAndMint() returns _firstMintedTokenId {

        uint256 quantity = 5;
        uint256 expectedFirstMintedTokenId = 1;

        uint256 mintedTokenId = myTokenContract.payAndMint(quantity);

        // Check that the function returns the correct first minted token ID
        assertEq(mintedTokenId, expectedFirstMintedTokenId, "First minted token ID is incorrect");

        // Check that the tokens were minted to the correct address
        assertEq(myTokenContract.balanceOf(to), quantity, "Tokens were not minted to the correct address");

        // Ensure that the tokens were minted correctly
        uint256 actualTokenId = myTokenContract.nextTokenId() - quantity;
        assertEq(actualTokenId, mintedTokenId, "The first minted token ID should match the expected value");

        emit Minted(msg.sender, quantity, firstMintedTokenId);

    }

    function testAdminMint () {
        uint256 quantity = 5;

        address nonAdmin = address(0x123);
        bool nonAdminMintResult = address(myTokenContract).call( abi.encodeWithSignature("adminMint(address,uint256)", nonAdmin, quantity) );
        assertFalse(nonAdminMintResult, "adminMint should revert when called by a non-owner and non-ADMIN_ROLE address");

        // Next, try to mint tokens from an ADMIN_ROLE address
        address admin = address(0x456);
        myTokenContract.grantRole(keccak256("ADMIN_ROLE"), admin);
        bool adminMintResult = address(myTokenContract).call( abi.encodeWithSignature("adminMint(address,uint256)", admin, quantity) );
        assertTrue(adminMintResult, "adminMint should succeed when called by an ADMIN_ROLE address");

    }

    // test airdropAdminMint(address[] calldata _to, uint256 _quantity)
    // Test the airdropAdminMint function
    function testAirdropAdminMint() public {
        // Define some sample addresses and quantity
        address[] memory addresses = [0x123, 0x456, 0x789];
        uint256 quantity = 100;

        // Call the airdropAdminMint function on myTokenContract instance
        uint256 firstMintedTokenId = myTokenContract.airdropAdminMint(addresses, quantity);

        // Assert that the firstMintedTokenId is not zero
        assertTrue(firstMintedTokenId != 0, "Invalid firstMintedTokenId");

        // Assert that the tokens were minted to the specified addresses
        for (uint256 i = 0; i < addresses.length; i++) {
            assertTrue(myTokenContract.balanceOf(addresses[i]) == quantity, "Invalid balance after minting");
        }
    }


    // test purchasePresale( uint256 quantity, uint256 maxQuantity, uint256 pricePerToken, bytes32[] calldata merklePro[of)
    function testPurchasePresale() public {        
        // Set up test data
        uint256 quantity = 1;
        uint256 maxQuantity = 10;
        uint256 pricePerToken = 100;
        bytes32[] memory merkleProof = new bytes32[](0);

        // Call the function with valid arguments
        myTokenContract.purchasePresale(quantity, maxQuantity, pricePerToken, merkleProof).value(pricePerToken * quantity)();

        // Assert that the function executed successfully and emitted the expected event
        assertSuccess();
        assertEmitted("Sale", (address(this), quantity, pricePerToken, 1));
    }

    // test  withdrawETH()
    function testWithdrawETH() external {

        myTokenContract = new ERC721ConsoleDrop();
        
        // Define console fee and funds remaining
        uint256 consoleFee = 100;
        uint256 fundsRemaining = 900;

        // Mock the console fee manager
        address consoleFeeManagerMock = address(this);
        consoleFeeManagerMock.mock( "getConsoleFeeManager()", bytes32(uint256(consoleFeeAddress)) );
        consoleFeeManagerMock.mock( "platformFee(uint128)", bytes32(consoleFee) );

        // Call the function
        myTokenContract.withdrawETH();

        // Assert that the console fee was paid out correctly
        assertEq(address(this).balance, consoleFee);

        // Assert that the remaining funds were paid out correctly
        assertEq(payoutAddress.balance, fundsRemaining - consoleFee);
    }

    // test reveal(string calldata baseURI_)
    function testReveal() public {

        myTokenContract = new ERC721ConsoleDrop();

        // Set up initial variables
        string memory baseURI = "https://example.com/";
        bool initialIsRevealed = myTokenContract.isRevealed();

        // Call the reveal function
        myTokenContract.reveal(baseURI);

        // Check that isRevealed has been set to true
        Assert.isTrue(myTokenContract.isRevealed(), "isRevealed should be true");

        // Check that the baseURI has been updated
        assertEq(myTokenContract.baseURIStorage(), baseURI, "baseURI should be updated");

        // Check that the URIUpdated event was emitted with the correct values
        EventAssertions.assertEventFired(myTokenContract, "URIUpdated", 1);
        EventAssertions.assertEventParameter(myTokenContract, "URIUpdated", "baseURI", baseURI);
        EventAssertions.assertEventParameter(myTokenContract, "URIUpdated", "isRevealed", true);
    }

    // test updatePreRevealContent(string memory baseURI_)
    function testUpdatePreRevealContent() public {
        string memory expectedURI = "https://example.com/api/v1/";
        contractToTest.updatePreRevealContent(expectedURI);
        string memory actualURI = contractToTest.baseURIStorage();
        assertEq(actualURI, expectedURI, "UpdatePreRevealContent function failed.");
    }

    // test testSetContractURI(string memory contractURI_)
    function testSetContractURI() public {
        string memory expectedURI = "https://example.com/api/v1/contract";
        contractToTest.setContractURI(expectedURI);
        string memory actualURI = contractToTest.contractURIStorage();
        assertEq(actualURI, expectedURI, "SetContractURI function failed.");
    }

    // test setBaseURI(string memory contractURI_)
    function testSetBaseURI() public {
        string memory expectedURI = "https://example.com/api/v1/base";
        contractToTest.setBaseURI(expectedURI);
        string memory actualURI = contractToTest.baseURIStorage();
        assertEq(actualURI, expectedURI, "SetBaseURI function failed.");
    }


    // test freezeMetadata()
    function testFreezeMetadata() public {
        contractToTest.freezeMetadata();
        bool actualFlag = contractToTest.isMetadataFrozen();
        assertEq(actualFlag, true, "FreezeMetadata function failed.");
    }

    // test setRoyalty(uint16 royaltyBPS_)
    function testSetRoyalty() public {
        uint16 expectedRoyalty = 500;
        contractToTest.setRoyalty(expectedRoyalty);
        uint16 actualRoyalty = contractToTest.royaltyBPS();
        assertEq(actualRoyalty, expectedRoyalty, "SetRoyalty function failed.");
    }
}
