// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdminSetupBaseTest} from "../../AdminSetupBaseTest.t.sol";

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Admin} from "../../../../../src/Admin.sol";

abstract contract PrepareUninstallationTest is AdminSetupBaseTest {
    function _payload(address _plugin) internal pure returns (IPluginSetup.SetupPayload memory) {
        return IPluginSetup.SetupPayload({plugin: _plugin, currentHelpers: new address[](0), data: ""});
    }

    function test_WhenPrepared() external {
        // it should revoke EXECUTE on the DAO and SET_TARGET_CONFIG on the plugin, in that order.
        PermissionLib.MultiTargetPermission[] memory permissions =
            setup.prepareUninstallation(address(dao), _payload(address(plugin)));
        assertEq(permissions.length, 2, "count");
        _assertPermission(
            permissions[0], PermissionLib.Operation.Revoke, address(dao), address(plugin), EXECUTE_PERMISSION_ID, "0"
        );
        _assertPermission(
            permissions[1],
            PermissionLib.Operation.Revoke,
            address(plugin),
            address(dao),
            SET_TARGET_CONFIG_PERMISSION_ID,
            "1"
        );
    }

    function test_WhenApplied() external {
        // it should leave the admin unable to act on the DAO, but still holding EXECUTE_PROPOSAL on the plugin.
        // FINDING: A5. The admin's permission on the (now inert) plugin is not revoked.
        PermissionLib.MultiTargetPermission[] memory permissions =
            setup.prepareUninstallation(address(dao), _payload(address(plugin)));
        vm.prank(manager);
        dao.applyMultiTargetPermissions(permissions);

        assertFalse(
            dao.hasPermission(address(dao), address(plugin), EXECUTE_PERMISSION_ID, ""), "plugin cannot execute"
        );
        assertFalse(dao.hasPermission(address(plugin), address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "no target");
        assertTrue(dao.hasPermission(address(plugin), admin, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "admin keeps it");
        assertTrue(plugin.isMember(admin), "still reported as member");

        vm.prank(admin);
        vm.expectRevert();
        plugin.executeProposal(PROPOSAL_METADATA, _actions(1), 0);
    }

    function testFuzz_WhenAnyPayload(address _plugin, bytes calldata _data) external {
        // it should only depend on the plugin address (no validation of the payload).
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: _plugin, currentHelpers: new address[](3), data: _data});
        PermissionLib.MultiTargetPermission[] memory permissions = setup.prepareUninstallation(address(dao), payload);
        assertEq(permissions.length, 2);
        assertEq(permissions[0].who, _plugin);
        assertEq(permissions[1].where, _plugin);
    }
}

contract PrepareUninstallation_AdminSetup_UnitTest is PrepareUninstallationTest {}

contract PrepareUninstallation_AdminSetupZkSync_UnitTest is PrepareUninstallationTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
