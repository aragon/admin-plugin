// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {AdminSetup} from "../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../src/zkSync/AdminSetupZkSync.sol";
import {Constants} from "../utils/Constants.sol";
import {ActionTarget} from "../utils/mocks/ActionTarget.sol";

/// @notice Forks the network selected with `just switch` and uses the live OSx framework and Admin repo.
/// @dev Run with `just test-fork` (addresses come from just-foundry's `networks/<network>.env`).
///      The code in `src/` is published as the next build of the live repo, as the management DAO would:
///      `AdminSetupZkSync` on zkSync (no EIP-1167 clones there), `AdminSetup` elsewhere.
contract ForkBaseTest is Constants, Test {
    uint8 internal constant RELEASE = 1;
    bytes4 internal constant PLACEHOLDER_SETUP_CANNOT_BE_USED = bytes4(keccak256("PlaceholderSetupCannotBeUsed()"));

    PluginRepo internal adminRepo;
    PluginSetupProcessor internal psp;
    DAOFactory internal daoFactory;
    address internal managementDao;

    /// @dev This repository's code, published on the fork as `localTag`.
    IPluginSetup internal localSetup;
    PluginRepo.Tag internal localTag;
    /// @dev The latest build published on the network before the fork test runs.
    uint16 internal latestPublishedBuild;

    ActionTarget internal actionTarget;
    address internal admin = makeAddr("admin");

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("RPC_URL"));

        adminRepo = PluginRepo(vm.envAddress("ADMIN_PLUGIN_REPO_ADDRESS"));
        psp = PluginSetupProcessor(vm.envAddress("PLUGIN_SETUP_PROCESSOR_ADDRESS"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY_ADDRESS"));
        managementDao = vm.envAddress("MANAGEMENT_DAO_ADDRESS");

        latestPublishedBuild = uint16(adminRepo.buildCount(RELEASE));
        bool zkSync = block.chainid == ZKSYNC_CHAIN_ID || block.chainid == ZKSYNC_SEPOLIA_CHAIN_ID;
        localSetup = zkSync ? IPluginSetup(address(new AdminSetupZkSync())) : IPluginSetup(address(new AdminSetup()));
        vm.prank(managementDao);
        adminRepo.createVersion(RELEASE, address(localSetup), "ipfs://fork-build", "");
        localTag = PluginRepo.Tag({release: RELEASE, build: latestPublishedBuild + 1});

        actionTarget = new ActionTarget();

        vm.label(address(adminRepo), "AdminRepo");
        vm.label(address(psp), "PSP");
        vm.label(address(daoFactory), "DAOFactory");
        vm.label(managementDao, "ManagementDAO");
    }

    // ==== DAO creation through the live DAOFactory ====

    function _createDao(PluginRepo.Tag memory _versionTag, bytes memory _installData)
        internal
        returns (DAO dao, address plugin)
    {
        DAOFactory.PluginSettings[] memory plugins = new DAOFactory.PluginSettings[](1);
        plugins[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({versionTag: _versionTag, pluginSetupRepo: adminRepo}), data: _installData
        });
        DAOFactory.InstalledPlugin[] memory installed;
        (dao, installed) = daoFactory.createDao(
            DAOFactory.DAOSettings({trustedForwarder: address(0), daoURI: "", subdomain: "", metadata: ""}), plugins
        );
        plugin = installed[0].plugin;
        vm.label(address(dao), "DAO");
        vm.label(plugin, "AdminPlugin");
    }

    /// @dev Installation data of every build: the admin and the target (zero address: the DAO).
    function _installData() internal view returns (bytes memory) {
        return abi.encode(admin, IPlugin.TargetConfig({target: address(0), operation: IPlugin.Operation.Call}));
    }

    /// @dev A build published with OSx's `PlaceholderSetup` (no plugin). Detected by its revert, not by
    ///      `implementation() == 0`, which `AdminSetupZkSync` also returns.
    function _isPlaceholder(uint16 _build) internal returns (bool) {
        address setup = adminRepo.getVersion(_tag(_build)).pluginSetup;
        try IPluginSetup(setup).prepareInstallation(address(0xdead), _installData()) {
            return false;
        } catch (bytes memory reason) {
            // Only the selector matters: the truncation is intended.
            // forge-lint: disable-next-line(unsafe-typecast)
            return reason.length >= 4 && bytes4(reason) == PLACEHOLDER_SETUP_CANNOT_BE_USED;
        }
    }

    function _tag(uint16 _build) internal pure returns (PluginRepo.Tag memory) {
        return PluginRepo.Tag({release: RELEASE, build: _build});
    }
}
