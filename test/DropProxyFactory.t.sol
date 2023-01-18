//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC721ConsoleDrop, IERC721ConsoleDrop} from "../src/ERC721ConsoleDrop.sol";
import {DropProxyFactory, IDropProxyFactory} from "../src/DropProxyFactory.sol";
import {IConsoleFeeManager} from "../src/interfaces/IConsoleFeeManager.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import "./TestConfig.sol";

contract TestDropProxyFactory is TestConfig {
    event ConsoleDropCreated(
        address indexed consoleDrop,
        address indexed deployer,
        bytes initData,
        address[] contracts,
        bytes[] data,
        bytes[] results
    );

    event ConsoleDropImplementationSet(address newImplementation);

    uint96 constant PRICE = 1 ether;
    uint32 constant START_TIME = 0;
    uint32 constant END_TIME = 10000;
    address constant SIGNER = address(111111);

    uint16 constant AFFILIATE_FEE_BPS = 0;

    // Tests that the factory deploys
    function test_deploysConsoleDropCreator() public {
        // Deploy logic contracts
        ERC721ConsoleDrop dropImplementation = new ERC721ConsoleDrop();
        DropProxyFactory _dropProxyFactory = new DropProxyFactory(
            address(dropImplementation)
        );

        assert(address(_dropProxyFactory) != address(0));
        assertEq(
            address(_dropProxyFactory.consoleDropImplementation()),
            address(dropImplementation)
        );
    }
}
