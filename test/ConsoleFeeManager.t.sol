// SPDX-License-identifier: MIT
pragma solidity 0.8.17;

import "./TestConfig.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ConsoleFeeManager, IConsoleFeeManager} from "../src/ConsoleFeeManager.sol";

contract TestConsoleFeeManger is TestConfig {
    event ConsoleFeeAddressSet(address consoleFeeAddress);

    event PlatformFeeSet(uint16 platformFeeBPS);

    function test_deployConsoleFeeManager(
        address consoleFeeAddress,
        uint16 platformFeeBPS
    ) public {
        if (consoleFeeAddress == address(0)) {
            vm.expectRevert(
                IConsoleFeeManager.InvalidConsoleFeeAddress.selector
            );
            new ConsoleFeeManager(consoleFeeAddress, platformFeeBPS);
            return;
        }
        if (platformFeeBPS > MAX_BPS) {
            vm.expectRevert(IConsoleFeeManager.InvalidPlatformFeeBPS.selector);
            new ConsoleFeeManager(consoleFeeAddress, platformFeeBPS);
            return;
        }

        ConsoleFeeManager consoleFeeManager = new ConsoleFeeManager(
            consoleFeeAddress,
            platformFeeBPS
        );

        assertEq(consoleFeeManager.consoleFeeAddress(), consoleFeeAddress);
        assertEq(consoleFeeManager.platformFeeBPS(), platformFeeBPS);
    }

    // =============================================================
    //                     setConsoleFeeAddress()
    // =============================================================

    // Test if setConsoleFeeAddress only callable by owner
    function test_setConsoleFeeAddressRevertsForNonOwner() external {
        address caller = getFundedAccount(1);
        vm.prank(caller);
        vm.expectRevert(0x82b42900);
        feeManager.setConsoleFeeAddress(address(10));
    }

    function test_setConsoleFeeAddress(address newConsoleFeeAddress) external {
        if (newConsoleFeeAddress == address(0)) {
            vm.expectRevert(
                IConsoleFeeManager.InvalidConsoleFeeAddress.selector
            );
            feeManager.setConsoleFeeAddress(newConsoleFeeAddress);
            return;
        }

        vm.expectEmit(false, false, false, true);
        emit ConsoleFeeAddressSet(newConsoleFeeAddress);
        feeManager.setConsoleFeeAddress(newConsoleFeeAddress);

        assertEq(feeManager.consoleFeeAddress(), newConsoleFeeAddress);
    }

    // =============================================================
    //                      setPlatformFeeBPS()
    // =============================================================

    // Test if setPlatformFeeBPS only callable by owner
    function test_setPlatformFeeBPSRevertsForNonOwner() external {
        address caller = getFundedAccount(1);
        vm.prank(caller);
        vm.expectRevert(0x82b42900);
        feeManager.setPlatformFeeBPS(10);
    }

    function test_setPlatformFeeBPS(uint16 newPlatformFeeBPS) external {
        if (newPlatformFeeBPS > MAX_BPS) {
            vm.expectRevert(IConsoleFeeManager.InvalidPlatformFeeBPS.selector);
            feeManager.setPlatformFeeBPS(newPlatformFeeBPS);
            return;
        }

        vm.expectEmit(false, false, false, true);
        emit PlatformFeeSet(newPlatformFeeBPS);
        feeManager.setPlatformFeeBPS(newPlatformFeeBPS);

        assertEq(feeManager.platformFeeBPS(), newPlatformFeeBPS);

        uint128 requiredEtherValue = 1 ether;
        assertEq(
            feeManager.platformFee(requiredEtherValue),
            (requiredEtherValue * newPlatformFeeBPS) / MAX_BPS
        );
    }
}
