// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PlaceholderSetup} from "@aragon/osx/framework/plugin/repo/placeholder/PlaceholderSetup.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {AdminSetup} from "../../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../../src/zkSync/AdminSetupZkSync.sol";
import {BaseScript} from "../../../script/Base.sol";
import {PluginSettings} from "../../../script/PluginSettings.sol";
import {NewVersionHarness} from "../../utils/harness/NewVersionHarness.sol";

/// @dev `createVersion` assigns the build number on-chain: `NewVersion.s.sol` must publish exactly as many
///      builds as needed for the setup to land on `VERSION_BUILD`, and refuse to run once it exists.
///      The proposal calldata is executed against the live management DAO multisig in `test/fork/newVersion.t.sol`.
contract NewVersion_Script_UnitTest is Test {
    bytes internal constant BUILD_METADATA = "ipfs://build";
    bytes internal constant RELEASE_METADATA = "ipfs://release";
    bytes internal constant PROPOSAL_METADATA = "ipfs://proposal";

    NewVersionHarness internal newVersion;
    PluginRepo internal repo;
    PlaceholderSetup internal previousSetup;
    AdminSetup internal newSetup;

    function setUp() public {
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        newVersion = new NewVersionHarness();
        repo = PluginRepo(
            address(new ERC1967Proxy(address(new PluginRepo()), abi.encodeCall(PluginRepo.initialize, (address(this)))))
        );
        previousSetup = new PlaceholderSetup();
        newSetup = new AdminSetup();
    }

    function _publishPreviousBuilds(uint256 _count) internal {
        for (uint256 i; i < _count; ++i) {
            repo.createVersion(PluginSettings.VERSION_RELEASE, address(previousSetup), "b", RELEASE_METADATA);
        }
    }

    function _expectInvalidBuild(uint256 _latestBuild) internal {
        vm.expectRevert(
            abi.encodeWithSelector(BaseScript.InvalidVersionBuild.selector, PluginSettings.VERSION_BUILD, _latestBuild)
        );
    }

    /// @dev Executes the printed actions as the maintainer (this test contract stands in for the management DAO).
    function _executeActions(uint256 _count) internal {
        Action[] memory actions =
            newVersion.exposed_createVersionActions(repo, address(newSetup), _count, BUILD_METADATA, RELEASE_METADATA);
        for (uint256 i; i < actions.length; ++i) {
            (bool ok,) = actions[i].to.call(actions[i].data);
            assertTrue(ok, "createVersion");
        }
    }

    function _setupOf(uint16 _build) internal view returns (address) {
        return repo.getVersion(PluginRepo.Tag(PluginSettings.VERSION_RELEASE, _build)).pluginSetup;
    }

    function test_WhenTheRepoIsOneBuildBehind() external {
        // it should publish a single build, landing on VERSION_BUILD.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD - 1);
        assertEq(newVersion.exposed_buildsToPublish(repo), 1, "builds to publish");
        _executeActions(1);
        assertEq(repo.buildCount(PluginSettings.VERSION_RELEASE), PluginSettings.VERSION_BUILD, "build count");
        assertEq(_setupOf(PluginSettings.VERSION_BUILD), address(newSetup), "new build");
    }

    function test_WhenTheReleaseHasNoBuilds() external {
        // it should fill every build up to VERSION_BUILD with the same setup.
        assertEq(newVersion.exposed_buildsToPublish(repo), PluginSettings.VERSION_BUILD, "builds to publish");
        _executeActions(PluginSettings.VERSION_BUILD);
        for (uint16 b = 1; b <= PluginSettings.VERSION_BUILD; ++b) {
            assertEq(_setupOf(b), address(newSetup), "every build");
        }
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_RevertWhen_TheVersionIsAlreadyPublished() external {
        // it should revert, publishing again would create VERSION_BUILD + 1.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_RevertWhen_TheRepoIsAheadOfTheVersion() external {
        // it should revert.
        _publishPreviousBuilds(PluginSettings.VERSION_BUILD + 1);
        _expectInvalidBuild(PluginSettings.VERSION_BUILD + 1);
        newVersion.exposed_buildsToPublish(repo);
    }

    function test_WhenBuildingTheActions() external view {
        // it should target the repo with createVersion and no value, once per build.
        Action[] memory actions =
            newVersion.exposed_createVersionActions(repo, address(newSetup), 3, BUILD_METADATA, RELEASE_METADATA);
        bytes memory expected = abi.encodeCall(
            PluginRepo.createVersion,
            (PluginSettings.VERSION_RELEASE, address(newSetup), BUILD_METADATA, RELEASE_METADATA)
        );
        assertEq(actions.length, 3, "count");
        for (uint256 i; i < 3; ++i) {
            assertEq(actions[i].to, address(repo), "to");
            assertEq(actions[i].value, 0, "value");
            assertEq(actions[i].data, expected, "data");
        }
    }

    function test_WhenBuildingTheProposalCalldata() external view {
        // it should encode the 7-argument createProposal of the management DAO multisig.
        Action[] memory actions =
            newVersion.exposed_createVersionActions(repo, address(newSetup), 1, BUILD_METADATA, RELEASE_METADATA);
        bytes memory data = newVersion.exposed_proposalCalldata(actions, PROPOSAL_METADATA, 1234);
        // The first 4 bytes are the selector: the truncation is intended.
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes4 selector = bytes4(data);
        assertEq(
            selector,
            bytes4(keccak256("createProposal(bytes,(address,uint256,bytes)[],uint256,bool,bool,uint64,uint64)")),
            "selector"
        );
        bytes memory args = new bytes(data.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = data[i + 4];
        }
        (
            bytes memory metadata,
            Action[] memory decoded,
            uint256 failureMap,
            bool approve,
            bool tryExec,
            uint64 start,
            uint64 end
        ) = abi.decode(args, (bytes, Action[], uint256, bool, bool, uint64, uint64));
        assertEq(metadata, PROPOSAL_METADATA, "metadata");
        assertEq(decoded.length, 1, "actions");
        assertEq(decoded[0].data, actions[0].data, "action");
        assertEq(failureMap, 0, "failure map");
        assertTrue(approve, "submitter approves");
        assertFalse(tryExec, "no execution on submission");
        assertEq(start, 0, "starts on submission");
        assertEq(end, 1234, "end date");
    }

    function test_WhenListingThePublishedVersions() external {
        // it should list the gap builds and VERSION_BUILD with the real setup; no implementation on zkSync.
        BaseScript.ArtifactVersion[] memory versions = newVersion.exposed_publishedVersions(address(newSetup), 2);
        assertEq(versions.length, 2, "count");
        for (uint256 i; i < 2; ++i) {
            assertEq(versions[i].build, PluginSettings.VERSION_BUILD - 1 + i, "build");
            assertEq(versions[i].setup, address(newSetup), "setup");
            assertEq(versions[i].implementation, newSetup.implementation(), "implementation");
            assertFalse(versions[i].placeholder, "real build");
        }

        AdminSetupZkSync zkSetup = new AdminSetupZkSync();
        versions = newVersion.exposed_publishedVersions(address(zkSetup), 1);
        assertEq(versions[0].implementation, address(0), "zkSync setup has no implementation");
    }
}
