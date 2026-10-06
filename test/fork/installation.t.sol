// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Admin} from "../../src/Admin.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev A DAO created through the live DAOFactory with this repository's Admin.
contract Installation_ForkTest is ForkBaseTest {
    DAO internal dao;
    Admin internal plugin;

    function setUp() public override {
        super.setUp();
        address installed;
        (dao, installed) = _createDao(localTag, _installData());
        plugin = Admin(installed);
    }

    function test_WhenInstalledThroughTheDaoFactory() external view {
        // it should wire the plugin to the new DAO, targeting it with a call.
        assertEq(address(plugin.dao()), address(dao), "dao");
        assertEq(plugin.getTargetConfig().target, address(dao), "effective target");
        assertEq(uint8(plugin.getTargetConfig().operation), uint8(IPlugin.Operation.Call), "call");
        assertTrue(plugin.isMember(admin), "admin is member");
        assertFalse(plugin.isMember(address(0xBEEF)), "outsider is not");
        bool zkSync = block.chainid == ZKSYNC_CHAIN_ID || block.chainid == ZKSYNC_SEPOLIA_CHAIN_ID;
        assertEq(
            uint8(plugin.pluginType()),
            uint8(zkSync ? IPlugin.PluginType.Constructable : IPlugin.PluginType.Cloneable),
            "plugin type"
        );
    }

    function test_WhenInstalled_ItShouldHoldExactlyTheSetupPermissions() external view {
        // it should grant what the setup prepares, and nothing else.
        address p = address(plugin);
        assertTrue(dao.hasPermission(p, admin, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "admin executes proposals");
        assertTrue(dao.hasPermission(p, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertTrue(dao.hasPermission(address(dao), p, EXECUTE_PERMISSION_ID, ""), "plugin executes on DAO");
        assertFalse(dao.hasPermission(p, address(0xBEEF), EXECUTE_PROPOSAL_PERMISSION_ID, ""), "outsider");
        assertFalse(dao.hasPermission(p, address(dao), EXECUTE_PROPOSAL_PERMISSION_ID, ""), "DAO is no admin");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "PSP has no ROOT");
        assertFalse(dao.hasPermission(address(dao), address(daoFactory), ROOT_PERMISSION_ID, ""), "factory has no ROOT");
    }

    function test_WhenTheAdminExecutes() external {
        // it should execute the actions through the DAO.
        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (42))});
        vm.prank(admin);
        plugin.executeProposal("ipfs://p", actions, 0);
        assertEq(actionTarget.value(), 42, "action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }

    function test_RevertWhen_SomeoneElseExecutes() external {
        // it should revert.
        Action[] memory actions = new Action[](0);
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), address(0xBEEF), EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.executeProposal("ipfs://p", actions, 0);
    }
}
