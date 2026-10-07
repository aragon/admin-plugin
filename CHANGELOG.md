# Admin Plugin

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to the [Aragon OSx Plugin Versioning Convention](https://devs.aragon.org/docs/osx/how-to-guides/plugin-development/publication/versioning).

## Unreleased

### Changed

- Migrated the project from Hardhat to Foundry: sources in `src/` and `src/zkSync/` (unchanged), tests rewritten in Solidity, deployment scripts in `script/` driven by `just` and `just-foundry`.
- OSx and osx-commons come from the `lib/osx` submodule.

### Fixed

- `build-metadata.json`: the `change` text was a placeholder, the admin input described the wrong permission, and the target config had wrong internal types. An explicit empty `prepareUpdate` was added (installations cannot be updated).

### Removed

- The `@aragon/admin-plugin-artifacts` npm package. ABIs and addresses are published in artifacts-hub.

## v1.2

### Added

- Copied files from [aragon/osx commit 1130df](https://github.com/aragon/osx/commit/1130dfce94fd294c4341e91a8f3faccc54cf43b7)
- `hasSucceeded`, `createProposal`, `customProposalParamsABI`, `canExecute` and `execute` functions implementing to `IProposal` interface.
- `initialize` function also receives `TargetConfig` with the optional target config.

### Changed

- Bumped OpenZepplin to `4.9.6`.
- Used `ProxyLib` from `osx-commons-contracts` for the minimal proxy deployment in `AdminSetup`.
- Hard-coded the `bytes32 internal constant EXECUTE_PERMISSION_ID` constant in `AdminSetup` until it is available in `PermissionLib`.
