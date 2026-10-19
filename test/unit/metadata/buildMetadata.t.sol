// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {BaseTest} from "../../BaseTest.t.sol";

import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";

import {Admin} from "../../../src/Admin.sol";
import {AdminSetup} from "../../../src/AdminSetup.sol";
import {AdminSetupZkSync} from "../../../src/zkSync/AdminSetupZkSync.sol";
import {CustomExecutorMock} from "../../utils/mocks/CustomExecutorMock.sol";

/// @notice The build metadata is the contract between UIs/scripts and the setup: a UI encodes the setup
///         payloads from these input types. The tests pin the declared types to what the contracts decode.
contract BuildMetadata_UnitTest is BaseTest {
    string internal buildMetadata;
    string internal releaseMetadata;

    function setUp() public override {
        super.setUp();
        buildMetadata = vm.readFile("script/metadata/build-metadata.json");
        releaseMetadata = vm.readFile("script/metadata/release-metadata.json");
    }

    // ==== Helpers ====

    /// @dev Canonical ABI type of the input at `_path` (tuples expanded recursively), e.g. `tuple(address,uint8)`.
    function _canonicalType(string memory _path) internal view returns (string memory) {
        string memory t = vm.parseJsonString(buildMetadata, string.concat(_path, ".type"));
        if (keccak256(bytes(t)) != keccak256("tuple")) return t;

        string memory inner;
        for (uint256 i;; ++i) {
            string memory component = string.concat(_path, ".components[", vm.toString(i), "]");
            if (!vm.keyExistsJson(buildMetadata, component)) break;
            inner = string.concat(inner, i == 0 ? "" : ",", _canonicalType(component));
        }
        return string.concat("tuple(", inner, ")");
    }

    /// @dev Comma-separated canonical types of all inputs at `_inputsPath`; every input must be described.
    function _signature(string memory _inputsPath) internal view returns (string memory sig) {
        for (uint256 i;; ++i) {
            string memory input = string.concat(_inputsPath, "[", vm.toString(i), "]");
            if (!vm.keyExistsJson(buildMetadata, input)) break;
            sig = string.concat(sig, i == 0 ? "" : ",", _canonicalType(input));
            assertGt(
                bytes(vm.parseJsonString(buildMetadata, string.concat(input, ".description"))).length,
                0,
                string.concat(input, " has no description")
            );
        }
    }

    // ==== prepareInstallation ====

    function test_WhenReadingTheInstallationInputs() external view {
        // it should declare exactly (address, (address,uint8)).
        assertEq(_signature(".pluginSetup.prepareInstallation.inputs"), "address,tuple(address,uint8)");
        assertGt(bytes(vm.parseJsonString(buildMetadata, ".pluginSetup.prepareInstallation.description")).length, 0);
    }

    function test_WhenReadingTheInstallationInternalTypes() external view {
        // it should name the OSx types the setup decodes.
        assertEq(
            vm.parseJsonString(buildMetadata, ".pluginSetup.prepareInstallation.inputs[1].internalType"),
            "struct IPlugin.TargetConfig"
        );
        assertEq(
            vm.parseJsonString(buildMetadata, ".pluginSetup.prepareInstallation.inputs[1].components[1].internalType"),
            "enum IPlugin.Operation"
        );
    }

    function test_WhenEncodingWithTheDeclaredInstallationTypes() external {
        // it should be accepted by both setups and land in the right fields.
        CustomExecutorMock executor = new CustomExecutorMock();
        bytes memory data = abi.encode(
            admin, IPlugin.TargetConfig({target: address(executor), operation: IPlugin.Operation.DelegateCall})
        );

        address[2] memory installed;
        (installed[0],) = new AdminSetup().prepareInstallation(address(dao), data);
        (installed[1],) = new AdminSetupZkSync().prepareInstallation(address(dao), data);
        for (uint256 i; i < 2; ++i) {
            Admin p = Admin(installed[i]);
            assertEq(address(p.dao()), address(dao), "dao");
            assertEq(p.getCurrentTargetConfig().target, address(executor), "target");
            assertEq(uint8(p.getCurrentTargetConfig().operation), uint8(IPlugin.Operation.DelegateCall), "operation");
        }
    }

    // ==== prepareUpdate / prepareUninstallation ====

    function test_WhenReadingTheUpdateEntries() external view {
        // it should declare no update path: Admin is not upgradeable.
        assertTrue(vm.keyExistsJson(buildMetadata, ".pluginSetup.prepareUpdate"), "present");
        assertEq(vm.parseJsonKeys(buildMetadata, ".pluginSetup.prepareUpdate").length, 0, "empty");
    }

    function test_WhenReadingTheUninstallationInputs() external view {
        // it should declare no inputs.
        assertEq(_signature(".pluginSetup.prepareUninstallation.inputs"), "");
    }

    function test_WhenReadingTheChangeText() external view {
        // it should describe the build (no placeholder text left).
        string memory change = vm.parseJsonString(buildMetadata, ".change");
        assertGt(bytes(change).length, 0, "change");
        assertEq(vm.indexOf(change, "PLACEHOLDER"), type(uint256).max, "no placeholder");
    }

    // ==== Release metadata ====

    function test_WhenReadingTheReleaseMetadata() external view {
        // it should have a non-empty name and description.
        assertEq(vm.parseJsonString(releaseMetadata, ".name"), "Admin", "name");
        assertGt(bytes(vm.parseJsonString(releaseMetadata, ".description")).length, 0, "description");
    }
}
