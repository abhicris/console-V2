// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC721ConsoleDrop} from "../src/interfaces/IERC721ConsoleDrop.sol";

contract GetInterfaceId is Script {
    function run() external view {
        console.log("{");

        /* solhint-disable quotes */
        console.log('"IERC721ConsoleDrop": "');
        console.logBytes4(type(IERC721ConsoleDrop).interfaceId);

        console.log('"}');
    }
}
