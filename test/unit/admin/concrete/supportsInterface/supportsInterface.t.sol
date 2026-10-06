// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

abstract contract SupportsInterfaceTest is BaseTest {
    function test_WhenQueryingTheBaseInterfaces() external view {
        // it should support ERC-165, IPlugin, IProtocolVersion and the target config functions.
        assertTrue(plugin.supportsInterface(IERC165_ID), "IERC165");
        assertTrue(plugin.supportsInterface(IPLUGIN_ID), "IPlugin");
        assertTrue(plugin.supportsInterface(IPROTOCOL_VERSION_ID), "IProtocolVersion");
        assertTrue(plugin.supportsInterface(TARGET_CONFIG_ID), "target config");
    }

    function test_WhenQueryingTheProposalInterfaces() external view {
        // it should support the current IProposal ID and the legacy (OSx v1.0) one, not the current minus proposalCount.
        assertTrue(plugin.supportsInterface(IPROPOSAL_ID), "IProposal");
        assertTrue(plugin.supportsInterface(IPROPOSAL_LEGACY_ID), "legacy IProposal");
        assertFalse(plugin.supportsInterface(IPROPOSAL_ID ^ IPROPOSAL_LEGACY_ID), "IProposal without proposalCount");
    }

    function test_WhenQueryingTheAdminInterfaces() external view {
        // it should support IMembership and the Admin ID (executeProposal).
        assertTrue(plugin.supportsInterface(IMEMBERSHIP_ID), "IMembership");
        assertTrue(plugin.supportsInterface(ADMIN_ID), "Admin");
    }

    function test_WhenQueryingUnsupportedInterfaces() external view {
        // it should not support the invalid ID, the plugin setup ID or unrelated IDs.
        assertFalse(plugin.supportsInterface(0xffffffff), "invalid");
        assertFalse(plugin.supportsInterface(IPLUGIN_SETUP_ID), "IPluginSetup");
        assertFalse(plugin.supportsInterface(bytes4(keccak256("upgradeTo(address)"))), "upgradeTo");
        assertFalse(plugin.supportsInterface(bytes4(0)), "zero");
    }
}

contract SupportsInterface_Admin_UnitTest is SupportsInterfaceTest {}

contract SupportsInterface_AdminZkSync_UnitTest is SupportsInterfaceTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
