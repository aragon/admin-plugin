// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {Admin} from "../src/Admin.sol";
import {AdminZkSync} from "../src/zkSync/AdminZkSync.sol";

import {Constants} from "./utils/Constants.sol";
import {ActionTarget} from "./utils/mocks/ActionTarget.sol";

/// @notice Shared fixture: a real DAO with an Admin plugin wired exactly like its setup does.
/// @dev Both variants share the same external behaviour: `Admin` (EIP-1167 clone, EVM chains) and
///      `AdminZkSync` (constructor-initialized, zkSync). Behaviour tests are written once in an abstract
///      contract and run for both by overriding `_isZkSyncVariant()`.
contract BaseTest is Constants, Test {
    using ProxyLib for address;

    address internal manager; // DAO root
    address internal admin; // holds EXECUTE_PROPOSAL_PERMISSION on the plugin
    address internal stranger;

    DAO internal dao;
    Admin internal plugin; // typed as Admin; AdminZkSync has the same external ABI
    ActionTarget internal actionTarget;

    /// @dev Override to run a suite against `AdminZkSync`.
    function _isZkSyncVariant() internal pure virtual returns (bool) {
        return false;
    }

    function setUp() public virtual {
        vm.roll(START_BLOCK);
        vm.warp(START_TIMESTAMP);

        manager = makeAddr("manager");
        admin = makeAddr("admin");
        stranger = makeAddr("stranger");

        dao = _deployDao(manager);
        actionTarget = new ActionTarget();

        plugin = _deployPlugin(dao, _daoTarget());
        _grantSetupPermissions(address(plugin), admin);

        vm.label(address(dao), "DAO");
        vm.label(address(plugin), _isZkSyncVariant() ? "AdminZkSync" : "Admin");
        vm.label(address(actionTarget), "ActionTarget");
    }

    // ==== Deployment helpers ====

    function _deployDao(address _root) internal returns (DAO) {
        return
            DAO(
                payable(new ERC1967Proxy(
                        address(new DAO()), abi.encodeCall(DAO.initialize, ("", _root, address(0), ""))
                    ))
            );
    }

    /// @dev Deploys the variant under test the way its setup does: a clone of a fresh `Admin` implementation,
    ///      or `new AdminZkSync(...)`.
    function _deployPlugin(DAO _dao, IPlugin.TargetConfig memory _targetConfig) internal returns (Admin) {
        if (_isZkSyncVariant()) {
            return Admin(address(new AdminZkSync(IDAO(address(_dao)), _targetConfig)));
        }
        return Admin(
            address(new Admin())
                .deployMinimalProxy(abi.encodeCall(Admin.initialize, (IDAO(address(_dao)), _targetConfig)))
        );
    }

    /// @dev Mirrors the permissions granted by `AdminSetup.prepareInstallation` / `AdminSetupZkSync`.
    function _grantSetupPermissions(address _plugin, address _admin) internal {
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](3);
        permissions[0] = _permission(PermissionLib.Operation.Grant, _plugin, _admin, EXECUTE_PROPOSAL_PERMISSION_ID);
        permissions[1] =
            _permission(PermissionLib.Operation.Grant, _plugin, address(dao), SET_TARGET_CONFIG_PERMISSION_ID);
        permissions[2] = _permission(PermissionLib.Operation.Grant, address(dao), _plugin, EXECUTE_PERMISSION_ID);

        vm.prank(manager);
        dao.applyMultiTargetPermissions(permissions);
    }

    function _permission(PermissionLib.Operation _operation, address _where, address _who, bytes32 _permissionId)
        internal
        pure
        returns (PermissionLib.MultiTargetPermission memory)
    {
        return PermissionLib.MultiTargetPermission({
            operation: _operation, where: _where, who: _who, condition: NO_CONDITION, permissionId: _permissionId
        });
    }

    function _grant(address _where, address _who, bytes32 _permissionId) internal {
        vm.prank(manager);
        dao.grant(_where, _who, _permissionId);
    }

    function _revoke(address _where, address _who, bytes32 _permissionId) internal {
        vm.prank(manager);
        dao.revoke(_where, _who, _permissionId);
    }

    // ==== Proposal helpers ====

    function _execute(address _caller, Action[] memory _actionList, uint256 _allowFailureMap)
        internal
        returns (uint256)
    {
        vm.prank(_caller);
        return plugin.executeProposal(PROPOSAL_METADATA, _actionList, _allowFailureMap);
    }

    /// @dev `_count` actions calling `actionTarget.setValue(i + 1)`.
    function _actions(uint256 _count) internal view returns (Action[] memory actionList) {
        actionList = new Action[](_count);
        for (uint256 i; i < _count; ++i) {
            actionList[i] =
                Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (i + 1))});
        }
    }

    function _failingAction() internal view returns (Action memory) {
        return Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.fail, ())});
    }

    /// @dev The proposal ID formula, written independently from `_createProposalId`.
    function _expectedProposalId(Action[] memory _actionList, bytes memory _metadata) internal view returns (uint256) {
        bytes32 salt = keccak256(abi.encode(_actionList, _metadata));
        return uint256(keccak256(abi.encode(block.chainid, block.number, address(plugin), salt)));
    }

    function _daoTarget() internal view returns (IPlugin.TargetConfig memory) {
        return IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call});
    }
}
