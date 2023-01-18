// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";

import {DropProxyFactory} from "../src/DropProxyFactory.sol";
import {ERC721ConsoleDrop} from "../src/ERC721ConsoleDrop.sol";
import {ConsoleFeeManager, IConsoleFeeManager} from "../src/ConsoleFeeManager.sol";
import {MockConsoleDrop} from "./mocks/MockConsoleDrop.sol";

contract TestConfig is Test {

    uint8 public constant METADATA_IS_FROZEN_FLAG = 1 << 0;
    uint8 public constant MINT_RANDOMNESS_ENABLED_FLAG = 1 << 1;

    // Artist contract creation vars
    string constant NAME = "CREATE";
    string constant SYMBOL = "CR8";
    string constant BASE_URI = "https://example.com/metadata/";
    string constant CONTRACT_URI = "https://example.com/storefront/";
    address constant PAYOUT_ADDRESS = address(99);
    uint16 constant ROYALTY_BPS = 100;
    address public constant ARTIST_ADMIN = address(8888888888);
    uint32 constant EDITION_MAX_MINTABLE = type(uint32).max;
    uint8 constant FLAGS = MINT_RANDOMNESS_ENABLED_FLAG;
    uint16 constant PLATFORM_FEE_BPS = 500;
    uint256 constant MAX_BPS = 10_000;

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

    SalesConfiguration public SALES_CONFIG =
        SalesConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: 0,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0,
            maxSalePurchasePerAddress: 0,
            presaleMerkleRoot: bytes32(0)
        });
    address constant CONSOLE_FEE_ADDRESS = address(2222222222);

    uint256 internal _salt;

    DropProxyFactory dropProxyFactory;
    ConsoleFeeManager feeManager;

    // Set up called before each test
    function setUp() public virtual {
        feeManager = new ConsoleFeeManager(
            CONSOLE_FEE_ADDRESS,
            PLATFORM_FEE_BPS
        );

        // Deploy ERC721ConsoleDrop implementation
        MockConsoleDrop dropImplementation = new MockConsoleDrop();

        dropProxyFactory = new DropProxyFactory(address(dropImplementation));
    }

    /**
     * @dev Returns an address funded with ETH
     * @param num Number used to generate the address (more convenient than passing address(num))
     */
    function getFundedAccount(uint256 num) public returns (address) {
        address addr = vm.addr(num);
        // Fund with some ETH
        vm.deal(addr, 1e19);

        return addr;
    }

    function createDrop(
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
    ) public returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            ERC721ConsoleDrop.initialize.selector,
            name_,
            symbol_,
            baseURI_,
            contractURI_,
            payoutAddress_,
            royaltyBPS_,
            _salesconfig,
            editionMaxMintable_,
            flags_,
            consoleFeeManager_
        );

        address[] memory contracts;
        bytes[] memory data;

        dropProxyFactory.createDrop(
            bytes32(++_salt),
            initData,
            contracts,
            data
        );
        (address addr, ) = dropProxyFactory.consoleDropAddress(
            address(this),
            bytes32(_salt)
        );
        return payable(addr);
    }

    function createGenericEdition() public returns (ERC721ConsoleDrop) {
        return
            ERC721ConsoleDrop(
                createDrop(
                    NAME,
                    SYMBOL,
                    BASE_URI,
                    CONTRACT_URI,
                    PAYOUT_ADDRESS,
                    ROYALTY_BPS,
                    SALES_CONFIG,
                    EDITION_MAX_MINTABLE,
                    FLAGS,
                    IConsoleFeeManager(CONSOLE_FEE_ADDRESS)
                )
            );
    }
}
