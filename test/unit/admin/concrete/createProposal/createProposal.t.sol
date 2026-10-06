// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

/// @dev The generic `IProposal.createProposal` overload: creates and executes at once, like `executeProposal`.
abstract contract CreateProposalTest is BaseTest {
    function _create(address _caller, Action[] memory _actionList, uint64 _start, uint64 _end, bytes memory _data)
        internal
        returns (uint256)
    {
        vm.prank(_caller);
        return plugin.createProposal(PROPOSAL_METADATA, _actionList, _start, _end, _data);
    }

    function _withFailingFirst() internal view returns (Action[] memory actionList) {
        actionList = new Action[](2);
        actionList[0] = _failingAction();
        actionList[1] = _actions(1)[0];
    }

    function test_RevertWhen_TheCallerLacksThePermission() external {
        // it should revert with DaoUnauthorized for the caller (the permission check uses the caller, not the plugin).
        Action[] memory actionList = _actions(1);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector, address(dao), address(plugin), stranger, EXECUTE_PROPOSAL_PERMISSION_ID
            )
        );
        plugin.createProposal(PROPOSAL_METADATA, actionList, 0, 0, "");
    }

    function test_WhenTheDataIsEmpty() external {
        // it should execute right away with a failure map of 0.
        uint256 id = _create(admin, _actions(1), 0, 0, "");
        assertEq(id, _expectedProposalId(_actions(1), PROPOSAL_METADATA), "id");
        assertEq(actionTarget.value(), 1, "executed");

        Action[] memory failing = _withFailingFirst();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(DAO.ActionFailed.selector, 0));
        plugin.createProposal(PROPOSAL_METADATA, failing, 0, 0, "");
    }

    function test_WhenTheDataEncodesAFailureMap() external {
        // it should pass it to the execution.
        _create(admin, _withFailingFirst(), 0, 0, abi.encode(uint256(1)));
        assertEq(actionTarget.value(), 1, "second action ran");
    }

    function test_WhenTheDataHasTrailingBytes() external {
        // it should ignore them (abi.decode does not check the length).
        _create(admin, _withFailingFirst(), 0, 0, abi.encodePacked(abi.encode(uint256(1)), bytes32("trailing")));
        assertEq(actionTarget.value(), 1, "decoded the first word");
    }

    function test_RevertWhen_TheDataIsTooShort() external {
        // it should revert without a reason.
        Action[] memory actionList = _actions(1);
        vm.prank(admin);
        vm.expectRevert();
        plugin.createProposal(PROPOSAL_METADATA, actionList, 0, 0, hex"01");
    }

    function test_WhenDatesAreGiven() external {
        // it should ignore them and execute now, emitting the current time as start and end.
        // FINDING: A3. A start date in the future, or an end date in the past, does not delay or prevent execution.
        Action[] memory actionList = _actions(1);
        uint256 id = _expectedProposalId(actionList, PROPOSAL_METADATA);
        vm.expectEmit(address(plugin));
        emit IProposal.ProposalCreated(
            id, admin, uint64(block.timestamp), uint64(block.timestamp), PROPOSAL_METADATA, actionList, 0
        );
        _create(admin, actionList, uint64(block.timestamp + 30 days), 1, "");
        assertEq(actionTarget.value(), 1, "executed immediately");
    }

    function testFuzz_WhenAnyDates(uint64 _start, uint64 _end) external {
        // it should behave exactly like executeProposal.
        uint256 id = _create(admin, _actions(1), _start, _end, "");
        assertEq(id, _expectedProposalId(_actions(1), PROPOSAL_METADATA));
        assertEq(actionTarget.value(), 1);
    }
}

contract CreateProposal_Admin_UnitTest is CreateProposalTest {}

contract CreateProposal_AdminZkSync_UnitTest is CreateProposalTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
