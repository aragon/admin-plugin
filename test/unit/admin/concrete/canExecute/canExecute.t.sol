// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {Admin} from "../../../../../src/Admin.sol";

abstract contract CanExecuteTest is BaseTest {
    function testFuzz_WhenQueriedForAnyId(uint256 _proposalId) external {
        // it should be true, although execute always reverts.
        // FINDING: A2. canExecute is true while execute(id) can never succeed.
        assertTrue(plugin.canExecute(_proposalId), "canExecute");
        vm.expectRevert(Admin.FunctionNotSupported.selector);
        plugin.execute(_proposalId);
    }
}

contract CanExecute_Admin_UnitTest is CanExecuteTest {}

contract CanExecute_AdminZkSync_UnitTest is CanExecuteTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
