// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../BaseTest.t.sol";

import {Vm} from "forge-std/Vm.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IExecutor, Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

/// @dev Fuzz tests of `executeProposal`, written once and run for both variants.
abstract contract Admin_FuzzTest is BaseTest {
    uint256 internal constant DAO_MAX_ACTIONS = 256;

    function testFuzz_WhenTheAdminExecutesAnyNumberOfActions(uint256 _count) external {
        // it should execute every action through the DAO, up to the DAO's maximum.
        _count = bound(_count, 0, DAO_MAX_ACTIONS);
        _execute(admin, _actions(_count), 0);
        assertEq(actionTarget.value(), _count, "last action ran");
        if (_count > 0) assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }

    function testFuzz_RevertWhen_MoreActionsThanTheDaoAccepts(uint256 _count) external {
        // it should revert with TooManyActions.
        _count = bound(_count, DAO_MAX_ACTIONS + 1, DAO_MAX_ACTIONS + 8);
        Action[] memory actionList = _actions(_count);
        vm.prank(admin);
        vm.expectRevert(DAO.TooManyActions.selector);
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
    }

    function testFuzz_WhenSomeActionsFail(uint256 _failingMask, uint256 _allowFailureMap, uint8 _count) external {
        // it should succeed iff every failing action is allowed to fail, reporting exactly the failed ones.
        uint256 count = bound(_count, 1, 16);
        _failingMask &= (uint256(1) << count) - 1;
        _allowFailureMap &= (uint256(1) << count) - 1;

        Action[] memory actionList = _actions(count);
        for (uint256 i; i < count; ++i) {
            if (_failingMask & (uint256(1) << i) != 0) actionList[i] = _failingAction();
        }

        bool shouldSucceed = (_failingMask & ~_allowFailureMap) == 0;
        if (!shouldSucceed) {
            uint256 firstForbidden;
            while ((_failingMask & ~_allowFailureMap) & (uint256(1) << firstForbidden) == 0) {
                ++firstForbidden;
            }
            vm.prank(admin);
            vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, firstForbidden));
            plugin.executeProposal(PROPOSAL_METADATA, actionList, _allowFailureMap);
            return;
        }

        vm.recordLogs();
        uint256 id = _execute(admin, actionList, _allowFailureMap);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(dao) || logs[i].topics[0] != IExecutor.Executed.selector) continue;
            (bytes32 callId,, uint256 allowFailureMap, uint256 failureMap,) =
                abi.decode(logs[i].data, (bytes32, Action[], uint256, uint256, bytes[]));
            assertEq(allowFailureMap, _allowFailureMap, "allow failure map forwarded");
            assertEq(callId, bytes32(id), "call id is the proposal id");
            assertEq(failureMap, _failingMask, "failure map reports the failed actions");
            found = true;
        }
        assertTrue(found, "DAO Executed emitted");
    }

    function testFuzz_ProposalIdFormula(bytes memory _metadata, uint8 _count, uint64 _blocks) external {
        // it should derive the id from chain, block, plugin, actions and metadata.
        vm.roll(block.number + bound(_blocks, 0, 1_000_000));
        Action[] memory actionList = _actions(bound(_count, 0, 8));
        uint256 expected = _expectedProposalId(actionList, _metadata);
        vm.prank(admin);
        assertEq(plugin.executeProposal(_metadata, actionList, 0), expected, "id");
    }

    function testFuzz_SameContentInTheSameBlockCollides(bytes memory _metadata, uint8 _count) external {
        // it should return the same id twice in one block and a different one in the next block.
        // FINDING: A1. Admin stores no proposals, so identical executions in one block share the proposal id
        // (and the DAO call id) without reverting.
        Action[] memory actionList = _actions(bound(_count, 0, 8));
        vm.startPrank(admin);
        uint256 first = plugin.executeProposal(_metadata, actionList, 0);
        uint256 second = plugin.executeProposal(_metadata, actionList, 0);
        vm.roll(block.number + 1);
        uint256 third = plugin.executeProposal(_metadata, actionList, 0);
        vm.stopPrank();

        assertEq(first, second, "same block, same id");
        assertTrue(first != third, "next block, new id");
    }

    function testFuzz_DifferentContentGivesDifferentIds(bytes memory _metadataA, bytes memory _metadataB) external {
        // it should give different ids to different metadata in the same block.
        vm.assume(keccak256(_metadataA) != keccak256(_metadataB));
        Action[] memory actionList = _actions(1);
        vm.startPrank(admin);
        uint256 a = plugin.executeProposal(_metadataA, actionList, 0);
        uint256 b = plugin.executeProposal(_metadataB, actionList, 0);
        vm.stopPrank();
        assertTrue(a != b, "distinct ids");
    }

    function testFuzz_RevertWhen_TheCallerIsNotAnAdmin(address _caller) external {
        // it should reject anyone without EXECUTE_PROPOSAL_PERMISSION.
        vm.assume(_caller != admin);
        Action[] memory actionList = _actions(1);
        vm.prank(_caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), _caller, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.executeProposal(PROPOSAL_METADATA, actionList, 0);
        assertFalse(plugin.isMember(_caller), "not a member");
    }

    function testFuzz_WhenCreatingThroughIProposal(uint64 _startDate, uint64 _endDate, uint256 _allowFailureMap)
        external
    {
        // it should execute immediately whatever the dates (finding A3), with the decoded failure map.
        // FINDING: A3. `createProposal` ignores the start and end dates.
        Action[] memory actionList = new Action[](2);
        actionList[0] = _failingAction();
        actionList[1] = _actions(1)[0];
        _allowFailureMap |= 1; // action 0 may fail
        vm.prank(admin);
        plugin.createProposal(PROPOSAL_METADATA, actionList, _startDate, _endDate, abi.encode(_allowFailureMap));
        assertEq(actionTarget.value(), 1, "executed now");
    }
}

contract Admin_Admin_FuzzTest is Admin_FuzzTest {}

contract Admin_AdminZkSync_FuzzTest is Admin_FuzzTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
