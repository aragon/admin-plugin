// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdminSetupBaseTest} from "../../AdminSetupBaseTest.t.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {Admin} from "../../../../../src/Admin.sol";
import {AdminSetup} from "../../../../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../../../../src/zkSync/AdminSetupZkSync.sol";

abstract contract ConstructorTest is AdminSetupBaseTest {
    function test_WhenQueryingTheInterfaces() external view {
        // it should support IPluginSetup, IProtocolVersion and ERC-165, nothing else.
        assertTrue(setup.supportsInterface(IPLUGIN_SETUP_ID), "IPluginSetup");
        assertTrue(setup.supportsInterface(IPROTOCOL_VERSION_ID), "IProtocolVersion");
        assertTrue(setup.supportsInterface(IERC165_ID), "IERC165");
        assertFalse(setup.supportsInterface(0xffffffff), "invalid");
        assertFalse(setup.supportsInterface(IPLUGIN_ID), "IPlugin");
        assertFalse(setup.supportsInterface(ADMIN_ID), "Admin");
    }

    function test_WhenQueryingTheExecuteProposalPermissionId() external view {
        // it should match the plugin's permission.
        bytes32 id = _isZkSyncVariant()
            ? AdminSetupZkSync(address(setup)).EXECUTE_PROPOSAL_PERMISSION_ID()
            : AdminSetup(address(setup)).EXECUTE_PROPOSAL_PERMISSION_ID();
        assertEq(id, EXECUTE_PROPOSAL_PERMISSION_ID);
    }
}

contract Constructor_AdminSetup_UnitTest is ConstructorTest {
    function test_WhenDeployed() external {
        // it should deploy an Admin implementation whose initializers are disabled.
        Admin implementation = Admin(setup.implementation());
        assertTrue(address(implementation).code.length > 0, "deployed");
        assertTrue(implementation.supportsInterface(ADMIN_ID), "is an Admin");
        assertEq(uint8(implementation.pluginType()), uint8(IPlugin.PluginType.Cloneable), "cloneable");
        vm.expectRevert("Initializable: contract is already initialized");
        implementation.initialize(IDAO(address(dao)), _daoTarget());
    }

    function test_WhenDeployedTwice() external {
        // it should deploy a separate implementation each time.
        assertTrue(new AdminSetup().implementation() != setup.implementation());
    }
}

contract Constructor_AdminSetupZkSync_UnitTest is ConstructorTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }

    function test_WhenDeployed() external view {
        // it should have no implementation: each installation deploys a full AdminZkSync.
        // FINDING: A8. implementation() is address(0), the same value as an OSx PlaceholderSetup.
        assertEq(setup.implementation(), address(0));
    }
}
