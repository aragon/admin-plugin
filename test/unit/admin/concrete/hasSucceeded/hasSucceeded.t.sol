// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

abstract contract HasSucceededTest is BaseTest {
    function testFuzz_WhenQueriedForAnyId(uint256 _proposalId) external view {
        // it should be true, even for ids that never existed.
        // FINDING: A2. Admin stores no proposals, so it cannot tell.
        assertTrue(plugin.hasSucceeded(_proposalId));
    }

    function test_WhenQueriedForAnExecutedProposal() external {
        // it should be true.
        uint256 id = _execute(admin, _actions(1), 0);
        assertTrue(plugin.hasSucceeded(id));
    }
}

contract HasSucceeded_Admin_UnitTest is HasSucceededTest {}

contract HasSucceeded_AdminZkSync_UnitTest is HasSucceededTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
