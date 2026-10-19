// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";

import {PluginSettings} from "../../script/PluginSettings.sol";
import {NewVersionHarness} from "../utils/harness/NewVersionHarness.sol";
import {ForkBaseTest} from "./ForkBaseTest.t.sol";

/// @dev The subset of the live management DAO multisig used here. Declared locally because the deployed
///      version may predate the Multisig plugin source available to this repository.
interface IManagementMultisig {
    struct MultisigSettings {
        bool onlyListed;
        uint16 minApprovals;
    }

    function addAddresses(address[] calldata _members) external;
    function updateMultisigSettings(MultisigSettings calldata _multisigSettings) external;
    function canExecute(uint256 _proposalId) external view returns (bool);
    function execute(uint256 _proposalId) external;
}

/// @dev Submits the calldata printed by `NewVersion.s.sol` to the live management DAO multisig and executes it:
///      proves that the hand-written `createProposal` signature and argument order match the deployed contract.
///      The multisig is reduced to a single test member (as the management DAO) so the proposal can pass here.
contract NewVersion_ForkTest is ForkBaseTest {
    NewVersionHarness internal newVersion;
    IManagementMultisig internal multisig;
    address internal member = makeAddr("member");

    function setUp() public override {
        super.setUp();
        if (vm.envOr("DEPLOYER_KEY", uint256(0)) == 0) vm.setEnv("DEPLOYER_KEY", vm.toString(uint256(1)));
        newVersion = new NewVersionHarness();
        multisig = IManagementMultisig(vm.envAddress("MANAGEMENT_DAO_MULTISIG_ADDRESS"));
        vm.label(address(multisig), "ManagementMultisig");

        address[] memory members = new address[](1);
        members[0] = member;
        vm.startPrank(managementDao);
        multisig.addAddresses(members);
        multisig.updateMultisigSettings(IManagementMultisig.MultisigSettings({onlyListed: true, minApprovals: 1}));
        vm.stopPrank();
        // Membership is read at the block before the proposal is created.
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 12);
    }

    function test_WhenTheManagementDaoMultisigExecutesTheProposal() external {
        // it should publish the setup as the next build of the live repo.
        uint8 release = PluginSettings.VERSION_RELEASE;
        uint256 buildsBefore = adminRepo.buildCount(release);
        address setup = address(localSetup);

        Action[] memory actions =
            newVersion.exposed_createVersionActions(adminRepo, setup, 1, "ipfs://build", "ipfs://release");
        uint64 endDate = uint64(block.timestamp + 30 days);
        bytes memory data = newVersion.exposed_proposalCalldata(actions, "ipfs://proposal", endDate);

        // Submitted as raw calldata, exactly as a member would with `cast send`.
        vm.prank(member);
        (bool ok, bytes memory ret) = address(multisig).call(data);
        assertTrue(ok, "createProposal accepts the calldata");
        uint256 proposalId = abi.decode(ret, (uint256));

        // approveProposal=true: the submitter's approval is enough with minApprovals = 1.
        // tryExecution=false: nothing is published until someone executes.
        assertEq(adminRepo.buildCount(release), buildsBefore, "not executed on submission");
        assertTrue(multisig.canExecute(proposalId), "executable");

        vm.prank(member);
        multisig.execute(proposalId);

        assertEq(adminRepo.buildCount(release), buildsBefore + 1, "build published");
        PluginRepo.Version memory latest = adminRepo.getLatestVersion(release);
        assertEq(latest.pluginSetup, setup, "setup");
        assertEq(latest.buildMetadata, "ipfs://build", "build metadata");
    }
}
