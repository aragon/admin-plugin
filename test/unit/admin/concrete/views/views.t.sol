// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

abstract contract ViewsTest is BaseTest {
    function test_WhenQueryingTheProtocolVersion() external view {
        // it should report OSx 1.4.0.
        uint8[3] memory version = plugin.protocolVersion();
        assertEq(version[0], 1);
        assertEq(version[1], 4);
        assertEq(version[2], 0);
    }

    function test_RevertWhen_QueryingTheProposalCount() external {
        // it should revert, proposalCount is deprecated (OSx 1.4) and Admin stores no proposals anyway.
        vm.expectRevert(bytes4(keccak256("FunctionDeprecated()")));
        plugin.proposalCount();
    }

    function test_WhenQueryingTheExecuteProposalPermissionId() external view {
        // it should match the permission the setup grants.
        assertEq(plugin.EXECUTE_PROPOSAL_PERMISSION_ID(), EXECUTE_PROPOSAL_PERMISSION_ID);
        assertEq(plugin.SET_TARGET_CONFIG_PERMISSION_ID(), SET_TARGET_CONFIG_PERMISSION_ID);
    }
}

contract Views_Admin_UnitTest is ViewsTest {
    function test_WhenQueryingThePluginType() external view {
        // it should be a clone.
        assertEq(uint8(plugin.pluginType()), uint8(IPlugin.PluginType.Cloneable));
    }
}

contract Views_AdminZkSync_UnitTest is ViewsTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }

    function test_WhenQueryingThePluginType() external view {
        // it should be constructable (no clones on zkSync).
        assertEq(uint8(plugin.pluginType()), uint8(IPlugin.PluginType.Constructable));
    }
}
