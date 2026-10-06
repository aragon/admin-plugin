// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Admin} from "../../../../../src/Admin.sol";

abstract contract ExecuteTest is BaseTest {
    function testFuzz_RevertWhen_Called(uint256 _proposalId) external {
        // it should always revert with FunctionNotSupported, for anyone, the admin included.
        vm.prank(admin);
        vm.expectRevert(Admin.FunctionNotSupported.selector);
        plugin.execute(_proposalId);
    }

    function test_RevertWhen_CalledForAnExecutedProposal() external {
        // it should revert too: proposals are executed in executeProposal, never later.
        uint256 id = _execute(admin, _actions(1), 0);
        vm.expectRevert(Admin.FunctionNotSupported.selector);
        plugin.execute(id);
        assertEq(actionTarget.value(), 1, "executed once");
    }
}

contract Execute_Admin_UnitTest is ExecuteTest {}

contract Execute_AdminZkSync_UnitTest is ExecuteTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
