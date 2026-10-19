// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {Plugin} from "@aragon/osx-commons-contracts/src/plugin/Plugin.sol";

import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

abstract contract SetTargetConfigTest is BaseTest {
    function test_RevertWhen_TheCallerLacksThePermission() external {
        // it should revert, the admin included (only the DAO holds SET_TARGET_CONFIG_PERMISSION).
        IPlugin.TargetConfig memory target = _daoTarget();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), admin, SET_TARGET_CONFIG_PERMISSION_ID
            )
        );
        plugin.setTargetConfig(target);
    }

    function test_WhenTheDaoSetsANewTarget() external {
        // it should store it, emit TargetSet and use it for the next execution.
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.Call});

        vm.expectEmit(address(plugin));
        emit Plugin.TargetSet(target);
        vm.prank(address(dao));
        plugin.setTargetConfig(target);

        assertEq(plugin.getTargetConfig().target, address(executor), "target");
        vm.expectEmit(address(executor));
        emit CustomExecutorMock.ExecutedCustom(
            address(executor), address(plugin), bytes32(_expectedProposalId(_actions(1), PROPOSAL_METADATA)), 1, 0
        );
        _execute(admin, _actions(1), 0);
        assertEq(actionTarget.value(), 0, "the DAO did not execute");
    }

    function test_RevertWhen_TheTargetIsTheDaoWithDelegateCall() external {
        // it should revert.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        vm.prank(address(dao));
        vm.expectRevert(abi.encodeWithSelector(Plugin.InvalidTargetConfig.selector, target));
        plugin.setTargetConfig(target);
    }

    function test_WhenTheTargetIsResetToZero() external {
        // it should fall back to the DAO with a call.
        vm.prank(address(dao));
        plugin.setTargetConfig(IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.DelegateCall}));
        assertEq(plugin.getTargetConfig().target, address(dao), "target");
        assertEq(uint8(plugin.getTargetConfig().operation), uint8(IPlugin.Operation.Call), "operation");
        _execute(admin, _actions(1), 0);
        assertEq(actionTarget.value(), 1, "executed through the DAO");
    }
}

contract SetTargetConfig_Admin_UnitTest is SetTargetConfigTest {}

contract SetTargetConfig_AdminZkSync_UnitTest is SetTargetConfigTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
