// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {Admin} from "../../src/Admin.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev Installations of every published build cannot be updated to this repository's code: the plugin is a
///      clone (or a constructed contract on zkSync) and the PSP only updates UUPS plugins.
contract Update_ForkTest is ForkBaseTest {
    DAO internal dao;
    Admin internal plugin;

    function _install(uint16 _build) internal {
        if (_isPlaceholder(_build)) {
            vm.skip(true, string.concat("build ", vm.toString(_build), " is a placeholder on this network"));
        }
        address installed;
        (dao, installed) = _createDao(_tag(_build), _installData());
        plugin = Admin(installed);
        vm.roll(block.number + 1);
    }

    function _assertUpdateRejectedAndStillWorking(uint16 _build) internal {
        vm.prank(address(dao));
        vm.expectRevert(abi.encodeWithSelector(PluginSetupProcessor.PluginNonupgradeable.selector, address(plugin)));
        psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: _tag(_build),
                newVersionTag: localTag,
                pluginSetupRepo: adminRepo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: address(plugin), currentHelpers: new address[](0), data: ""
                })
            })
        );

        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (5))});
        // Low-level call: build 1 (OSx v1.0) has the same selector but returns nothing.
        vm.prank(admin);
        (bool ok,) = address(plugin).call(abi.encodeCall(Admin.executeProposal, ("ipfs://after", actions, 0)));
        assertTrue(ok, "executeProposal");
        assertEq(actionTarget.value(), 5, "still executes");
    }

    function test_RevertWhen_UpdatingFromBuild1() external {
        // it should reject the update (finding A7); the plugin keeps working.
        // FINDING: A7. Installations cannot move to a new build; DAOs must uninstall and reinstall.
        _install(1);
        _assertUpdateRejectedAndStillWorking(1);
    }

    function test_RevertWhen_UpdatingFromBuild2() external {
        // it should reject the update (finding A7); the plugin keeps working.
        _install(2);
        _assertUpdateRejectedAndStillWorking(2);
    }
}
