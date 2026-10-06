// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdminSetupBaseTest} from "../../AdminSetupBaseTest.t.sol";

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

/// @dev Admin is not upgradeable (clone or plain contract): updates are refused by the setup itself.
abstract contract PrepareUpdateTest is AdminSetupBaseTest {
    function testFuzz_RevertWhen_PreparingAnyUpdate(uint16 _fromBuild, bytes calldata _data) external {
        // it should revert with NonUpgradeablePlugin, whatever the source build and payload.
        // FINDING: A7. Installations can never be updated in place.
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: address(plugin), currentHelpers: new address[](0), data: _data});
        vm.expectRevert(PluginSetup.NonUpgradeablePlugin.selector);
        setup.prepareUpdate(address(dao), _fromBuild, payload);
    }
}

contract PrepareUpdate_AdminSetup_UnitTest is PrepareUpdateTest {}

contract PrepareUpdate_AdminSetupZkSync_UnitTest is PrepareUpdateTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
