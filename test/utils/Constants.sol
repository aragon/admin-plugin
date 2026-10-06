// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Values the tests assert against. Computed from their definitions (strings and signatures),
///         never read from the contracts under test, so that a change in the contracts is caught.
abstract contract Constants {
    // Permissions
    bytes32 internal constant ROOT_PERMISSION_ID = keccak256("ROOT_PERMISSION");
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
    bytes32 internal constant EXECUTE_PROPOSAL_PERMISSION_ID = keccak256("EXECUTE_PROPOSAL_PERMISSION");
    bytes32 internal constant SET_TARGET_CONFIG_PERMISSION_ID = keccak256("SET_TARGET_CONFIG_PERMISSION");
    bytes32 internal constant UPGRADE_PLUGIN_PERMISSION_ID = keccak256("UPGRADE_PLUGIN_PERMISSION");

    address internal constant ANY_ADDR = address(type(uint160).max);
    address internal constant NO_CONDITION = address(0);

    // ERC-165 interface IDs
    bytes4 internal constant IERC165_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 internal constant IPLUGIN_ID = bytes4(keccak256("pluginType()"));
    bytes4 internal constant IPROTOCOL_VERSION_ID = bytes4(keccak256("protocolVersion()"));
    bytes4 internal constant TARGET_CONFIG_ID = bytes4(keccak256("setTargetConfig((address,uint8))"))
        ^ bytes4(keccak256("getTargetConfig()")) ^ bytes4(keccak256("getCurrentTargetConfig()"));
    bytes4 internal constant IMEMBERSHIP_ID = bytes4(keccak256("isMember(address)"));
    bytes4 internal constant IPROPOSAL_ID = bytes4(
        keccak256("createProposal(bytes,(address,uint256,bytes)[],uint64,uint64,bytes)")
    ) ^ bytes4(keccak256("hasSucceeded(uint256)")) ^ bytes4(keccak256("execute(uint256)"))
    ^ bytes4(keccak256("canExecute(uint256)")) ^ bytes4(keccak256("customProposalParamsABI()"))
    ^ bytes4(keccak256("proposalCount()"));
    /// @dev OSx v1.0 IProposal (only `proposalCount()`), still advertised by the proposal base for compatibility.
    bytes4 internal constant IPROPOSAL_LEGACY_ID = bytes4(keccak256("proposalCount()"));
    bytes4 internal constant ADMIN_ID = bytes4(keccak256("executeProposal(bytes,(address,uint256,bytes)[],uint256)"));
    bytes4 internal constant IPLUGIN_SETUP_ID = bytes4(keccak256("prepareInstallation(address,bytes)"))
        ^ bytes4(keccak256("prepareUpdate(address,uint16,(address,address[],bytes))"))
        ^ bytes4(keccak256("prepareUninstallation(address,(address,address[],bytes))"))
        ^ bytes4(keccak256("implementation()"));

    // Chains without EIP-1167 clone support (zkSync Era mainnet and sepolia)
    uint256 internal constant ZKSYNC_CHAIN_ID = 324;
    uint256 internal constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;

    // Defaults
    bytes internal constant PROPOSAL_METADATA = "ipfs://proposal-metadata";
    uint256 internal constant START_BLOCK = 100;
    uint256 internal constant START_TIMESTAMP = 1_700_000_000;
}
