// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {AdminSetupBaseTest} from "../../AdminSetupBaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";

import {Admin} from "../../../../../src/Admin.sol";
import {AdminSetup} from "../../../../../src/AdminSetup.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

abstract contract PrepareInstallationTest is AdminSetupBaseTest {
    function _prepare(bytes memory _data) internal returns (address, IPluginSetup.PreparedSetupData memory) {
        return setup.prepareInstallation(address(dao), _data);
    }

    function test_WhenTheDataIsValid() external {
        // it should return exactly three permissions, in order, without conditions, and no helpers.
        (address deployed, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_installData(admin, _daoTarget()));

        assertEq(prepared.helpers.length, 0, "no helpers");
        assertEq(prepared.permissions.length, 3, "permissions");
        _assertPermission(
            prepared.permissions[0], PermissionLib.Operation.Grant, deployed, admin, EXECUTE_PROPOSAL_PERMISSION_ID, "0"
        );
        _assertPermission(
            prepared.permissions[1],
            PermissionLib.Operation.Grant,
            deployed,
            address(dao),
            SET_TARGET_CONFIG_PERMISSION_ID,
            "1"
        );
        _assertPermission(
            prepared.permissions[2], PermissionLib.Operation.Grant, address(dao), deployed, EXECUTE_PERMISSION_ID, "2"
        );
    }

    function test_WhenTheDataIsValid_ThePluginIsInitialized() external {
        // it should deploy a plugin bound to the DAO with the given target config.
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall});
        (address deployed,) = _prepare(_installData(admin, target));

        Admin installed = Admin(deployed);
        assertEq(address(installed.dao()), address(dao), "dao");
        assertEq(installed.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(installed.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "op");
        assertTrue(installed.supportsInterface(ADMIN_ID), "is an Admin");
        assertEq(
            uint8(installed.pluginType()),
            uint8(_isZkSyncVariant() ? IPlugin.PluginType.Constructable : IPlugin.PluginType.Cloneable),
            "type"
        );
    }

    function test_WhenThePermissionsAreApplied() external {
        // it should let the admin execute through the DAO.
        (address deployed, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_installData(admin, _daoTarget()));
        vm.prank(manager);
        dao.applyMultiTargetPermissions(prepared.permissions);

        vm.prank(admin);
        Admin(deployed).executeProposal(PROPOSAL_METADATA, _actions(1), 0);
        assertEq(actionTarget.value(), 1, "executed");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }

    function test_WhenPreparedTwice() external {
        // it should deploy a distinct plugin each time.
        (address first,) = _prepare(_installData(admin, _daoTarget()));
        (address second,) = _prepare(_installData(admin, _daoTarget()));
        assertTrue(first != second, "distinct");
    }

    function test_RevertWhen_TheAdminIsTheZeroAddress() external {
        // it should revert with AdminAddressInvalid.
        bytes memory data = _installData(address(0), _daoTarget());
        vm.expectRevert(abi.encodeWithSelector(AdminSetup.AdminAddressInvalid.selector, address(0)));
        setup.prepareInstallation(address(dao), data);
    }

    function test_RevertWhen_TheDataIsEmptyOrTooShort() external {
        // it should revert when decoding.
        vm.expectRevert();
        setup.prepareInstallation(address(dao), "");
        bytes memory short = abi.encode(admin);
        vm.expectRevert();
        setup.prepareInstallation(address(dao), short);
    }

    function test_RevertWhen_TheTargetIsTheDaoWithDelegateCall() external {
        // it should revert when initializing the plugin.
        bytes memory data = _installData(
            admin, IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall})
        );
        vm.expectRevert();
        setup.prepareInstallation(address(dao), data);
    }

    function test_WhenTheAdminIsAnyNonZeroAddress() external {
        // it should accept it without further checks, the DAO itself included.
        (, IPluginSetup.PreparedSetupData memory prepared) = _prepare(_installData(address(dao), _daoTarget()));
        assertEq(prepared.permissions[0].who, address(dao));
    }
}

contract PrepareInstallation_AdminSetup_UnitTest is PrepareInstallationTest {}

contract PrepareInstallation_AdminSetupZkSync_UnitTest is PrepareInstallationTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }
}
