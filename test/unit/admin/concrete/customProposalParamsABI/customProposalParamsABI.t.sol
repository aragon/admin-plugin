// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

abstract contract CustomProposalParamsABITest is BaseTest {
    function test_WhenQueried() external view {
        // it should describe the only custom parameter, the failure map.
        assertEq(plugin.customProposalParamsABI(), "(uint256 allowFailureMap)");
    }
}

contract CustomProposalParamsABI_Admin_UnitTest is CustomProposalParamsABITest {}

contract CustomProposalParamsABI_AdminZkSync_UnitTest is CustomProposalParamsABITest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
