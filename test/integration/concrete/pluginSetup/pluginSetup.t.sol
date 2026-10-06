// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../../BaseTest.t.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef, hashHelpers} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {DAOMock} from "../../../../lib/osx/test/mocks/commons/dao/DAOMock.sol";

import {Admin} from "../../../../src/Admin.sol";
import {AdminSetup} from "../../../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../../../src/zkSync/AdminSetupZkSync.sol";
import {ActionTarget} from "../../../utils/mocks/ActionTarget.sol";

/// @notice Install, use, update and uninstall the plugin through a real, locally deployed PluginSetupProcessor.
/// @dev Build 1 is the setup under test, build 2 republishes it (UI-only update), build 3 is a fresh setup
///      (a real update, which a non-upgradeable plugin cannot take). Runs for both setups.
abstract contract PluginSetup_IntegrationTest is BaseTest {
    bytes32 internal constant APPLY_INSTALLATION_PERMISSION_ID = keccak256("APPLY_INSTALLATION_PERMISSION");
    bytes32 internal constant APPLY_UPDATE_PERMISSION_ID = keccak256("APPLY_UPDATE_PERMISSION");
    bytes32 internal constant APPLY_UNINSTALLATION_PERMISSION_ID = keccak256("APPLY_UNINSTALLATION_PERMISSION");

    PluginSetupProcessor internal psp;
    PluginRepo internal repo;
    IPluginSetup internal setupV1;
    IPluginSetup internal setupV3;

    function _newSetup() internal virtual returns (IPluginSetup);

    function setUp() public override {
        super.setUp();

        // Framework without ENS: an allow-all managing DAO and no subdomain registrar.
        DAOMock managingDao = new DAOMock();
        managingDao.setHasPermissionReturnValueMock(true);
        PluginRepoRegistry registry = PluginRepoRegistry(
            address(
                new ERC1967Proxy(
                    address(new PluginRepoRegistry()),
                    abi.encodeCall(
                        PluginRepoRegistry.initialize, (IDAO(address(managingDao)), ENSSubdomainRegistrar(address(0)))
                    )
                )
            )
        );
        psp = new PluginSetupProcessor(registry);
        PluginRepoFactory factory = new PluginRepoFactory(registry);

        setupV1 = _newSetup();
        setupV3 = _newSetup();
        repo = factory.createPluginRepoWithFirstVersion("", address(setupV1), address(this), hex"11", hex"11");
        repo.createVersion(1, address(setupV1), hex"22", "");
        repo.createVersion(1, address(setupV3), hex"33", "");

        _grant(address(psp), manager, APPLY_INSTALLATION_PERMISSION_ID);
        _grant(address(psp), manager, APPLY_UPDATE_PERMISSION_ID);
        _grant(address(psp), manager, APPLY_UNINSTALLATION_PERMISSION_ID);

        vm.label(address(psp), "PSP");
        vm.label(address(repo), "PluginRepo");
    }

    // ==== Helpers ====

    function _ref(uint16 _build) internal view returns (PluginSetupRef memory) {
        return PluginSetupRef({versionTag: PluginRepo.Tag({release: 1, build: _build}), pluginSetupRepo: repo});
    }

    function _install() internal returns (Admin installed) {
        bytes memory data = abi.encode(admin, _daoTarget());
        (address pluginAddress, IPluginSetup.PreparedSetupData memory prepared) = psp.prepareInstallation(
            address(dao), PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: _ref(1), data: data})
        );
        assertEq(prepared.helpers.length, 0, "no helpers");

        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        vm.prank(manager);
        psp.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams({
                pluginSetupRef: _ref(1),
                plugin: pluginAddress,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
        _revoke(address(dao), address(psp), ROOT_PERMISSION_ID);
        return Admin(pluginAddress);
    }

    function _prepareUpdate(Admin _plugin, uint16 _from, uint16 _to)
        internal
        returns (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared)
    {
        return psp.prepareUpdate(
            address(dao),
            PluginSetupProcessor.PrepareUpdateParams({
                currentVersionTag: PluginRepo.Tag({release: 1, build: _from}),
                newVersionTag: PluginRepo.Tag({release: 1, build: _to}),
                pluginSetupRepo: repo,
                setupPayload: IPluginSetup.SetupPayload({
                    plugin: address(_plugin), currentHelpers: new address[](0), data: ""
                })
            })
        );
    }

    function _uninstall(Admin _plugin, uint16 _build) internal {
        vm.roll(block.number + 1);
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: address(_plugin), currentHelpers: new address[](0), data: ""});
        PermissionLib.MultiTargetPermission[] memory permissions = psp.prepareUninstallation(
            address(dao),
            PluginSetupProcessor.PrepareUninstallationParams({pluginSetupRef: _ref(_build), setupPayload: payload})
        );
        _grant(address(dao), address(psp), ROOT_PERMISSION_ID);
        vm.prank(manager);
        psp.applyUninstallation(
            address(dao),
            PluginSetupProcessor.ApplyUninstallationParams({
                plugin: address(_plugin), pluginSetupRef: _ref(_build), permissions: permissions
            })
        );
        _revoke(address(dao), address(psp), ROOT_PERMISSION_ID);
    }

    function _assertInstalledPermissions(Admin _plugin) internal view {
        address p = address(_plugin);
        assertTrue(dao.hasPermission(p, admin, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "admin executes proposals");
        assertTrue(dao.hasPermission(p, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config");
        assertTrue(dao.hasPermission(address(dao), p, EXECUTE_PERMISSION_ID, ""), "plugin executes on DAO");
        assertFalse(dao.hasPermission(p, stranger, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "stranger");
        assertFalse(dao.hasPermission(p, address(dao), EXECUTE_PROPOSAL_PERMISSION_ID, ""), "DAO is no admin");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "PSP has no ROOT");
    }

    function _useEndToEnd(Admin _plugin, uint256 _value) internal {
        Action[] memory actions = new Action[](1);
        actions[0] =
            Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (_value))});
        vm.prank(admin);
        _plugin.executeProposal(PROPOSAL_METADATA, actions, 0);
        assertEq(actionTarget.value(), _value, "action ran");
        assertEq(actionTarget.lastCaller(), address(dao), "through the DAO");
    }

    // ==== Tests ====

    function test_WhenInstalledThroughThePsp() external {
        // it should wire the plugin to the DAO with exactly the setup permissions, and work end to end.
        Admin installed = _install();
        assertEq(address(installed.dao()), address(dao), "dao");
        assertEq(installed.getTargetConfig().target, address(dao), "target");
        assertTrue(installed.isMember(admin), "admin is member");
        _assertInstalledPermissions(installed);
        _useEndToEnd(installed, 7);
    }

    function test_RevertWhen_ApplyingAUiOnlyUpdate() external {
        // it should prepare the UI-only update (same setup) but revert when applying it (finding A9).
        // FINDING: A9. `PluginSetupProcessor.applyUpdate` calls `implementation()` on the plugin, which clone-based
        // and constructed plugins do not have, so even an update between two builds of the same setup cannot be
        // applied. Installations stay on the build they were installed with.
        Admin installed = _install();
        vm.roll(block.number + 1);
        (bytes memory initData, IPluginSetup.PreparedSetupData memory prepared) = _prepareUpdate(installed, 1, 2);
        assertEq(initData.length, 0, "no init data");
        assertEq(prepared.permissions.length, 0, "no permissions");

        (bool ok,) = address(installed).staticcall(abi.encodeWithSignature("implementation()"));
        assertFalse(ok, "the plugin has no implementation()");

        vm.prank(manager);
        vm.expectRevert();
        psp.applyUpdate(
            address(dao),
            PluginSetupProcessor.ApplyUpdateParams({
                plugin: address(installed),
                pluginSetupRef: _ref(2),
                initData: initData,
                permissions: prepared.permissions,
                helpersHash: hashHelpers(prepared.helpers)
            })
        );
        _assertInstalledPermissions(installed);
        _useEndToEnd(installed, 8);
    }

    function test_RevertWhen_UpdatingToADifferentSetup() external {
        // it should revert: a clone (or constructed) plugin cannot be upgraded (finding A7).
        // FINDING: A7. Installations cannot move to a build with a different setup; DAOs must uninstall and reinstall.
        Admin installed = _install();
        vm.roll(block.number + 1);
        vm.expectRevert(abi.encodeWithSelector(PluginSetupProcessor.PluginNonupgradeable.selector, address(installed)));
        _prepareUpdate(installed, 1, 3);

        // and the plugin keeps working.
        _useEndToEnd(installed, 9);
    }

    function test_WhenUninstalled() external {
        // it should revoke EXECUTE on the DAO and SET_TARGET_CONFIG; the admin keeps EXECUTE_PROPOSAL but can no
        // longer act.
        Admin installed = _install();
        _uninstall(installed, 1);

        address p = address(installed);
        assertFalse(dao.hasPermission(address(dao), p, EXECUTE_PERMISSION_ID, ""), "execute on DAO revoked");
        assertFalse(dao.hasPermission(p, address(dao), SET_TARGET_CONFIG_PERMISSION_ID, ""), "target config revoked");
        // FINDING: A5. Uninstallation leaves EXECUTE_PROPOSAL_PERMISSION with the admin (documented in the setup).
        assertTrue(dao.hasPermission(p, admin, EXECUTE_PROPOSAL_PERMISSION_ID, ""), "admin keeps it");
        assertTrue(installed.isMember(admin), "still reported as member");
        assertFalse(dao.hasPermission(address(dao), address(psp), ROOT_PERMISSION_ID, ""), "PSP has no ROOT");

        Action[] memory actions = new Action[](1);
        actions[0] = Action({to: address(actionTarget), value: 0, data: abi.encodeCall(ActionTarget.setValue, (1))});
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(PermissionManager.Unauthorized.selector, address(dao), p, EXECUTE_PERMISSION_ID)
        );
        installed.executeProposal(PROPOSAL_METADATA, actions, 0);
    }

    function test_RevertWhen_InstallingWithTheZeroAdmin() external {
        // it should revert with AdminAddressInvalid at preparation.
        bytes memory data = abi.encode(address(0), _daoTarget());
        vm.expectRevert(abi.encodeWithSelector(AdminSetup.AdminAddressInvalid.selector, address(0)));
        psp.prepareInstallation(
            address(dao), PluginSetupProcessor.PrepareInstallationParams({pluginSetupRef: _ref(1), data: data})
        );
    }
}

contract PluginSetup_Admin_IntegrationTest is PluginSetup_IntegrationTest {
    function _newSetup() internal override returns (IPluginSetup) {
        return IPluginSetup(address(new AdminSetup()));
    }

    function test_WhenInstalled_ThePluginIsAClone() external {
        // it should deploy an EIP-1167 clone of the setup's implementation.
        Admin installed = _install();
        bytes memory code = address(installed).code;
        assertEq(code.length, 45, "minimal proxy runtime");
        address implementation;
        assembly {
            implementation := shr(96, mload(add(code, 42)))
        }
        assertEq(implementation, AdminSetup(address(setupV1)).implementation(), "points to the implementation");
        assertEq(uint8(installed.pluginType()), uint8(IPlugin.PluginType.Cloneable), "cloneable");
    }
}

contract PluginSetup_AdminZkSync_IntegrationTest is PluginSetup_IntegrationTest {
    function _newSetup() internal override returns (IPluginSetup) {
        return IPluginSetup(address(new AdminSetupZkSync()));
    }

    function test_WhenInstalled_ThePluginIsConstructed() external {
        // it should deploy a standalone plugin; the setup exposes no implementation.
        Admin installed = _install();
        assertEq(AdminSetupZkSync(address(setupV1)).implementation(), address(0), "no implementation");
        assertGt(address(installed).code.length, 45, "full contract, not a proxy");
        assertEq(uint8(installed.pluginType()), uint8(IPlugin.PluginType.Constructable), "constructable");
    }
}
