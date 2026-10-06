// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {AdminSetup} from "../../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../../src/zkSync/AdminSetupZkSync.sol";

/// @notice Shared helpers for the setup tests, run against `AdminSetup` and `AdminSetupZkSync`
///         (switch with `_isZkSyncVariant()`).
abstract contract AdminSetupBaseTest is BaseTest {
    PluginSetup internal setup;

    function setUp() public virtual override {
        super.setUp();
        setup =
            _isZkSyncVariant() ? PluginSetup(address(new AdminSetupZkSync())) : PluginSetup(address(new AdminSetup()));
        vm.label(address(setup), _isZkSyncVariant() ? "AdminSetupZkSync" : "AdminSetup");
    }

    function _installData(address _admin, IPlugin.TargetConfig memory _targetConfig)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(_admin, _targetConfig);
    }

    function _assertPermission(
        PermissionLib.MultiTargetPermission memory _actual,
        PermissionLib.Operation _operation,
        address _where,
        address _who,
        bytes32 _permissionId,
        string memory _label
    ) internal pure {
        assertEq(uint8(_actual.operation), uint8(_operation), string.concat(_label, ": operation"));
        assertEq(_actual.where, _where, string.concat(_label, ": where"));
        assertEq(_actual.who, _who, string.concat(_label, ": who"));
        assertEq(_actual.condition, NO_CONDITION, string.concat(_label, ": condition"));
        assertEq(_actual.permissionId, _permissionId, string.concat(_label, ": permissionId"));
    }
}
