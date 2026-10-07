// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";

import {PermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/PermissionCondition.sol";
import {IPermissionCondition} from "@aragon/osx-commons-contracts/src/permission/condition/IPermissionCondition.sol";

/// @dev Grants only when the checked calldata is (non) empty, to observe the calldata isMember passes.
contract CalldataLengthCondition is PermissionCondition {
    bool public immutable REQUIRE_EMPTY;

    constructor(bool _requireEmpty) {
        REQUIRE_EMPTY = _requireEmpty;
    }

    function isGranted(address, address, bytes32, bytes calldata _data) public view override returns (bool) {
        return REQUIRE_EMPTY ? _data.length == 0 : _data.length > 0;
    }
}

abstract contract IsMemberTest is BaseTest {
    function test_WhenTheAccountHoldsTheExecuteProposalPermission() external view {
        // it should be a member.
        assertTrue(plugin.isMember(admin), "admin");
    }

    function test_WhenTheAccountDoesNotHoldIt() external view {
        // it should not be a member (the DAO and the manager included).
        assertFalse(plugin.isMember(stranger), "stranger");
        assertFalse(plugin.isMember(address(dao)), "dao");
        assertFalse(plugin.isMember(manager), "manager");
        assertFalse(plugin.isMember(address(0)), "zero");
    }

    function test_WhenThePermissionIsRevoked() external {
        // it should stop being a member.
        _revoke(address(plugin), admin, EXECUTE_PROPOSAL_PERMISSION_ID);
        assertFalse(plugin.isMember(admin));
    }

    function test_WhenThePermissionIsGrantedToAnyAddress() external {
        // it should make every address a member.
        // FINDING: A6. isMember mirrors the permission, so an ANY_ADDR grant makes everyone a member.
        _grant(address(plugin), ANY_ADDR, EXECUTE_PROPOSAL_PERMISSION_ID);
        assertTrue(plugin.isMember(stranger), "stranger");
        assertTrue(plugin.isMember(address(0xBEEF)), "anyone");
    }

    function test_WhenTheGrantHasAConditionReadingTheCalldata() external {
        // it should evaluate the condition with empty calldata, which can disagree with what executeProposal allows.
        // FINDING: A6. isMember passes "" as calldata while executeProposal passes its own calldata.
        address nonEmptyOnly = makeAddr("nonEmptyOnly");
        address emptyOnly = makeAddr("emptyOnly");
        vm.startPrank(manager);
        dao.grantWithCondition(
            address(plugin),
            nonEmptyOnly,
            EXECUTE_PROPOSAL_PERMISSION_ID,
            IPermissionCondition(address(new CalldataLengthCondition(false)))
        );
        dao.grantWithCondition(
            address(plugin),
            emptyOnly,
            EXECUTE_PROPOSAL_PERMISSION_ID,
            IPermissionCondition(address(new CalldataLengthCondition(true)))
        );
        vm.stopPrank();

        assertFalse(plugin.isMember(nonEmptyOnly), "not reported as member");
        _execute(nonEmptyOnly, _actions(1), 0);
        assertEq(actionTarget.value(), 1, "yet it can execute");

        assertTrue(plugin.isMember(emptyOnly), "reported as member");
        vm.prank(emptyOnly);
        vm.expectRevert();
        plugin.executeProposal(PROPOSAL_METADATA, _actions(1), 0);
    }
}

contract IsMember_Admin_UnitTest is IsMemberTest {}

contract IsMember_AdminZkSync_UnitTest is IsMemberTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
