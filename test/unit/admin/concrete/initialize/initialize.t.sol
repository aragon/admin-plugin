// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../../BaseTest.t.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {Plugin} from "@aragon/osx-commons-contracts/src/plugin/Plugin.sol";
import {PluginCloneable} from "@aragon/osx-commons-contracts/src/plugin/PluginCloneable.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {Admin} from "../../../../../src/Admin.sol";
import {AdminZkSync} from "../../../../../src/zkSync/AdminZkSync.sol";
import {CustomExecutorMock} from "../../../../utils/mocks/CustomExecutorMock.sol";

/// @dev `Admin` is an EIP-1167 clone initialized once through `initialize`.
contract Initialize_Admin_UnitTest is BaseTest {
    using ProxyLib for address;

    address internal implementation;

    function setUp() public override {
        super.setUp();
        implementation = address(new Admin());
    }

    function _clone(IPlugin.TargetConfig memory _targetConfig) internal returns (Admin) {
        return
            Admin(
                implementation.deployMinimalProxy(abi.encodeCall(Admin.initialize, (IDAO(address(dao)), _targetConfig)))
            );
    }

    function test_RevertWhen_CalledOnTheImplementation() external {
        // it should revert, the constructor disables initializers.
        vm.expectRevert("Initializable: contract is already initialized");
        Admin(implementation).initialize(IDAO(address(dao)), _daoTarget());
    }

    function test_RevertWhen_CalledTwice() external {
        // it should revert.
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(IDAO(address(dao)), _daoTarget());
    }

    function test_RevertWhen_AnyoneReinitializesWithAnotherDao() external {
        // it should revert, so nobody can take over a clone by re-pointing it to their own DAO.
        vm.prank(stranger);
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize(IDAO(stranger), _daoTarget());
    }

    function test_WhenInitialized() external {
        // it should store the DAO and the target config.
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall});
        Admin clone = _clone(target);

        assertEq(address(clone.dao()), address(dao), "dao");
        assertEq(clone.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(clone.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "operation");
        assertEq(uint8(clone.pluginType()), uint8(IPlugin.PluginType.Cloneable), "pluginType");
    }

    function test_WhenInitialized_ItShouldEmitEvents() external {
        // it should emit TargetSet and MembershipContractAnnounced(dao), in that order.
        address expected = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));

        vm.expectEmit(expected);
        emit PluginCloneable.TargetSet(_daoTarget());
        vm.expectEmit(expected);
        emit IMembership.MembershipContractAnnounced(address(dao));
        Admin clone = _clone(_daoTarget());
        assertEq(address(clone), expected, "precomputed");
    }

    function test_RevertWhen_TheTargetIsTheDaoWithDelegateCall() external {
        // it should revert, the plugin would be bricked.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        vm.expectRevert(abi.encodeWithSelector(PluginCloneable.InvalidTargetConfig.selector, target));
        this.externalClone(target);
    }

    function externalClone(IPlugin.TargetConfig memory _targetConfig) external returns (Admin) {
        return _clone(_targetConfig);
    }

    function test_WhenTheTargetIsTheZeroAddress() external {
        // it should fall back to the DAO with a call.
        Admin clone = _clone(IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.DelegateCall}));
        assertEq(clone.getTargetConfig().target, address(dao), "effective target");
        assertEq(uint8(clone.getTargetConfig().operation), uint8(IPlugin.Operation.Call), "effective operation");
    }

    function test_WhenTwoClonesShareTheImplementation() external {
        // it should keep their state separate.
        Admin a = _clone(_daoTarget());
        DAO other = _deployDao(manager);
        Admin b = Admin(
            implementation.deployMinimalProxy(abi.encodeCall(Admin.initialize, (IDAO(address(other)), _daoTarget())))
        );
        assertEq(address(a.dao()), address(dao), "a");
        assertEq(address(b.dao()), address(other), "b");
    }
}

/// @dev `AdminZkSync` (zkSync, no clones) is initialized in its constructor.
contract Constructor_AdminZkSync_UnitTest is BaseTest {
    function _isZkSyncVariant() internal pure override returns (bool) {
        return true;
    }

    function test_WhenDeployed() external {
        // it should store the DAO and the target config.
        CustomExecutorMock executor = new CustomExecutorMock();
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall});
        AdminZkSync deployed = new AdminZkSync(IDAO(address(dao)), target);

        assertEq(address(deployed.dao()), address(dao), "dao");
        assertEq(deployed.getCurrentTargetConfig().target, address(executor), "target");
        assertEq(uint8(deployed.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "operation");
        assertEq(uint8(deployed.pluginType()), uint8(IPlugin.PluginType.Constructable), "pluginType");
    }

    function test_WhenDeployed_ItShouldEmitEvents() external {
        // it should emit TargetSet and MembershipContractAnnounced(dao), in that order.
        address expected = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectEmit(expected);
        emit Plugin.TargetSet(_daoTarget());
        vm.expectEmit(expected);
        emit IMembership.MembershipContractAnnounced(address(dao));
        new AdminZkSync(IDAO(address(dao)), _daoTarget());
    }

    function test_RevertWhen_TheTargetIsTheDaoWithDelegateCall() external {
        // it should revert.
        IPlugin.TargetConfig memory target =
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.DelegateCall});
        vm.expectRevert(abi.encodeWithSelector(Plugin.InvalidTargetConfig.selector, target));
        new AdminZkSync(IDAO(address(dao)), target);
    }

    function test_WhenTheTargetIsTheZeroAddress() external {
        // it should fall back to the DAO with a call.
        AdminZkSync deployed = new AdminZkSync(
            IDAO(address(dao)), IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.DelegateCall})
        );
        assertEq(deployed.getTargetConfig().target, address(dao), "effective target");
        assertEq(uint8(deployed.getTargetConfig().operation), uint8(IPlugin.Operation.Call), "effective operation");
    }

    function test_WhenDeployed_ItHasNoInitializer() external {
        // it should expose no initialize function (constructor-only), so it can never be re-pointed.
        (bool ok,) = address(plugin).call(abi.encodeCall(Admin.initialize, (IDAO(stranger), _daoTarget())));
        assertFalse(ok, "no initialize");
        assertEq(address(plugin.dao()), address(dao), "dao unchanged");
    }
}
