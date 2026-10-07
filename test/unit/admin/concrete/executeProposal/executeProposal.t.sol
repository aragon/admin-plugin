// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Vm} from "forge-std/Vm.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action, IExecutor} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {Admin} from "../../../../../src/Admin.sol";
import {ActionTarget} from "../../../../utils/mocks/ActionTarget.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

abstract contract ExecuteProposalTest is BaseTest {
    uint256 internal constant DAO_MAX_ACTIONS = 256;

    function _setTarget(address _target, IPlugin.Operation _operation) internal {
        vm.prank(address(dao));
        plugin.setTargetConfig(IPlugin.TargetConfig({target: _target, operation: _operation}));
    }

    // ==== Authorization ====

    function test_RevertWhen_TheCallerLacksTheExecuteProposalPermission() external {
        // it should revert with DaoUnauthorized.
        Action[] memory actionList = _actions(1);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), stranger, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    function test_RevertWhen_TheDaoCallsWithoutThePermission() external {
        // it should revert too: holding ROOT or EXECUTE on the DAO is not enough.
        Action[] memory actionList = _actions(1);
        vm.prank(address(dao));
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), address(dao), EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    function test_RevertWhen_ThePluginLacksExecuteOnTheDao() external {
        // it should revert in the DAO.
        _revoke(address(dao), address(plugin), EXECUTE_PERMISSION_ID);
        Action[] memory actionList = _actions(1);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                PermissionManager.Unauthorized.selector, address(dao), address(plugin), EXECUTE_PERMISSION_ID
            )
        );
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    function test_WhenThePermissionIsRevokedFromTheAdmin() external {
        // it should no longer let the admin execute.
        _revoke(address(plugin), admin, EXECUTE_PROPOSAL_PERMISSION_ID);
        Action[] memory actionList = _actions(1);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), admin, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    // ==== Execution ====

    function test_WhenTheAdminExecutes() external {
        // it should execute every action through the DAO and return the proposal ID.
        Action[] memory actionList = _actions(3);
        uint256 expected = _expectedProposalId(actionList, PROPOSAL_METADATA);
        uint256 id = _execute(admin, actionList, 0);

        assertEq(id, expected, "id formula");
        assertEq(actionTarget.value(), 3, "last action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }

    function test_WhenTheAdminExecutes_ItShouldEmitInOrder() external {
        // it should emit DAO Executed (callId = proposal ID), then ProposalCreated, then ProposalExecuted.
        // FINDING: A4. ProposalCreated comes after the execution.
        Action[] memory actionList = _actions(2);
        uint256 id = _expectedProposalId(actionList, PROPOSAL_METADATA);

        vm.expectEmit(address(dao));
        emit IExecutor.Executed(address(plugin), bytes32(id), actionList, 5, 0, _results(2));
        vm.expectEmit(address(plugin));
        emit IProposal.ProposalCreated(
            id, admin, uint64(block.timestamp), uint64(block.timestamp), PROPOSAL_METADATA, actionList, 5
        );
        vm.expectEmit(address(plugin));
        emit IProposal.ProposalExecuted(id);
        _execute(admin, actionList, 5);

        vm.recordLogs();
        _execute(admin, actionList, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 executedAt = type(uint256).max;
        uint256 createdAt = type(uint256).max;
        uint256 doneAt = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IExecutor.Executed.selector) executedAt = i;
            if (logs[i].topics[0] == IProposal.ProposalCreated.selector) createdAt = i;
            if (logs[i].topics[0] == IProposal.ProposalExecuted.selector) doneAt = i;
        }
        assertLt(executedAt, createdAt, "Executed before ProposalCreated");
        assertLt(createdAt, doneAt, "ProposalCreated before ProposalExecuted");
    }

    function _results(uint256 _count) internal pure returns (bytes[] memory results) {
        results = new bytes[](_count);
    }

    function test_WhenTheSameProposalIsExecutedTwiceInOneBlock() external {
        // it should execute both and give them the same ID and DAO call ID.
        // FINDING: A1. Admin stores no proposals, so the ID collision is not detected.
        Action[] memory actionList = _actions(1);
        vm.recordLogs();
        uint256 first = _execute(admin, actionList, 0);
        uint256 second = _execute(admin, actionList, 0);
        assertEq(first, second, "same ID");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 executions;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(dao) && logs[i].topics[0] == IExecutor.Executed.selector) {
                (bytes32 callId,,,,) = abi.decode(logs[i].data, (bytes32, Action[], uint256, uint256, bytes[]));
                assertEq(callId, bytes32(first), "same call ID");
                ++executions;
            }
        }
        assertEq(executions, 2, "both executed");
    }

    function test_WhenTheSameProposalIsExecutedInTheNextBlock() external {
        // it should get a different ID.
        Action[] memory actionList = _actions(1);
        uint256 first = _execute(admin, actionList, 0);
        vm.roll(block.number + 1);
        assertTrue(_execute(admin, actionList, 0) != first);
    }

    function test_WhenOnlyTheMetadataDiffers() external {
        // it should get a different ID.
        Action[] memory actionList = _actions(1);
        uint256 first = _execute(admin, actionList, 0);
        vm.prank(admin);
        assertTrue(plugin.executeProposal("other", actionList, 0) != first);
    }

    function test_WhenTheFailureMapAllowsAFailingAction() external {
        // it should execute the rest.
        Action[] memory actionList = new Action[](2);
        actionList[0] = _failingAction();
        actionList[1] = _actions(1)[0];
        _execute(admin, actionList, 1);
        assertEq(actionTarget.value(), 1, "second action ran");
    }

    function test_RevertWhen_AFailingActionIsNotAllowed() external {
        // it should revert with the index of the action.
        Action[] memory actionList = new Action[](2);
        actionList[0] = _actions(1)[0];
        actionList[1] = _failingAction();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 1));
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 1); // bit 0 only
    }

    function test_WhenThereAreNoActions() external {
        // it should still emit the proposal events (a signalling proposal).
        Action[] memory none = new Action[](0);
        uint256 id = _expectedProposalId(none, PROPOSAL_METADATA);
        vm.expectEmit(address(plugin));
        emit IProposal.ProposalExecuted(id);
        _execute(admin, none, 0);
    }

    function test_WhenThereAreExactlyTheMaximumActions() external {
        // it should execute all 256.
        _execute(admin, _actions(DAO_MAX_ACTIONS), 0);
        assertEq(actionTarget.value(), DAO_MAX_ACTIONS);
    }

    function test_RevertWhen_ThereAreMoreActionsThanTheDaoAccepts() external {
        // it should revert with TooManyActions.
        Action[] memory actionList = _actions(DAO_MAX_ACTIONS + 1);
        vm.prank(admin);
        vm.expectRevert(DAO.TooManyActions.selector);
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    function test_WhenAnActionSendsNativeTokens() external {
        // it should transfer the value from the DAO.
        vm.deal(address(dao), 1 ether);
        Action[] memory actionList = _actions(1);
        actionList[0].value = 0.25 ether;
        _execute(admin, actionList, 0);
        assertEq(address(actionTarget).balance, 0.25 ether, "received");
        assertEq(address(dao).balance, 0.75 ether, "DAO paid");
    }

    function test_RevertWhen_AnActionReentersExecuteProposal() external {
        // it should revert: the DAO's reentrancy guard rejects the nested execution.
        _grant(address(plugin), address(actionTarget), EXECUTE_PROPOSAL_PERMISSION_ID);
        Action[] memory inner = _actions(1);
        Action[] memory outer = new Action[](1);
        outer[0] = Action({
            to: address(actionTarget),
            value: 0,
            data: abi.encodeCall(
                ActionTarget.callBack,
                (address(plugin), abi.encodeCall(Admin.executeProposal, (bytes("inner"), inner, uint256(0))))
            )
        });

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 0));
        plugin.executeProposal(PROPOSAL_METADATA, outer, 0);

        // With the failure allowed, the outer proposal completes and the inner one never ran.
        _execute(admin, outer, 1);
        assertEq(actionTarget.value(), 0, "inner never executed");
    }

    function test_WhenAReentrantActionMayFail() external {
        // it should record DAO.ReentrantCall as the reason the nested execution failed.
        _grant(address(plugin), address(actionTarget), EXECUTE_PROPOSAL_PERMISSION_ID);
        Action[] memory inner = _actions(1);
        Action[] memory outer = new Action[](1);
        outer[0] = Action({
            to: address(actionTarget),
            value: 0,
            data: abi.encodeCall(
                ActionTarget.callBack,
                (address(plugin), abi.encodeCall(Admin.executeProposal, (bytes("inner"), inner, uint256(0))))
            )
        });
        vm.recordLogs();
        _execute(admin, outer, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(dao) && logs[i].topics[0] == IExecutor.Executed.selector) {
                (,,, uint256 failureMap, bytes[] memory results) =
                    abi.decode(logs[i].data, (bytes32, Action[], uint256, uint256, bytes[]));
                assertEq(failureMap, 1, "action 0 failed");
                assertEq(bytes4(results[0]), DAO.ReentrantCall.selector, "ReentrantCall");
            }
        }
    }

    // ==== Target config ====

    function test_WhenTheTargetIsACustomExecutorWithCall() external {
        // it should call the executor from the plugin, not the DAO.
        CustomExecutorMock executor = new CustomExecutorMock();
        _setTarget(address(executor), IPlugin.Operation.Call);
        Action[] memory actionList = _actions(2);
        uint256 id = _expectedProposalId(actionList, PROPOSAL_METADATA);

        vm.expectEmit(address(executor));
        emit CustomExecutorMock.ExecutedCustom(address(executor), address(plugin), bytes32(id), 2, 3);
        _execute(admin, actionList, 3);
        assertEq(actionTarget.value(), 0, "DAO not used");
    }

    function test_WhenTheTargetIsACustomExecutorWithDelegateCall() external {
        // it should run the executor's code in the plugin's context, called by the admin.
        CustomExecutorMock executor = new CustomExecutorMock();
        _setTarget(address(executor), IPlugin.Operation.DelegateCall);
        Action[] memory actionList = _actions(1);
        uint256 id = _expectedProposalId(actionList, PROPOSAL_METADATA);

        vm.expectEmit(address(plugin));
        emit CustomExecutorMock.ExecutedCustom(address(plugin), admin, bytes32(id), 1, 0);
        _execute(admin, actionList, 0);
    }

    function test_RevertWhen_TheCustomExecutorReverts() external {
        // it should bubble the executor's error, with call and with delegatecall.
        CustomExecutorMock executor = new CustomExecutorMock();
        uint256 revertMap = executor.REVERT_FAILURE_MAP();
        Action[] memory actionList = _actions(1);

        _setTarget(address(executor), IPlugin.Operation.Call);
        vm.prank(admin);
        vm.expectRevert(CustomExecutorMock.FailedCustom.selector);
        plugin.executeProposal(PROPOSAL_METADATA, actionList, revertMap);

        _setTarget(address(executor), IPlugin.Operation.DelegateCall);
        vm.prank(admin);
        vm.expectRevert(CustomExecutorMock.FailedCustom.selector);
        plugin.executeProposal(PROPOSAL_METADATA, actionList, revertMap);
    }

    // ==== Fuzz ====

    function testFuzz_WhenAnyMetadataAndFailureMap(bytes calldata _metadata, uint256 _allowFailureMap) external {
        // it should execute and emit the inputs unchanged.
        Action[] memory actionList = _actions(1);
        uint256 id = _expectedProposalId(actionList, _metadata);
        vm.expectEmit(address(plugin));
        emit IProposal.ProposalCreated(
            id, admin, uint64(block.timestamp), uint64(block.timestamp), _metadata, actionList, _allowFailureMap
        );
        vm.prank(admin);
        assertEq(plugin.executeProposal(_metadata, actionList, _allowFailureMap), id);
    }
}

contract ExecuteProposal_Admin_UnitTest is ExecuteProposalTest {}

contract ExecuteProposal_AdminZkSync_UnitTest is ExecuteProposalTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
