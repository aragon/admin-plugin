# Admin Plugin [![Foundry][foundry-badge]][foundry] [![License: AGPL v3][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/AGPL-v3
[license-badge]: https://img.shields.io/badge/License-AGPL_v3-blue.svg

An Aragon OSx governance plugin that gives a single account (the admin) the power to execute actions on the DAO directly, without voting. Proposals execute when they are created.

Documentation: [protocol-doc, Admin Plugin](https://github.com/aragon/protocol-doc/blob/main/plugins/admin-plugin.md).

## Audit

### v1.2.0

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [546cfa243a5d0726d75158db646573ca2237f570](https://github.com/aragon/admin-plugin/commit/546cfa243a5d0726d75158db646573ca2237f570)
- Started: 2024-11-18
- Finished: 2025-02-13

`src/Admin.sol` and `src/AdminSetup.sol` are identical to the audited commit. The zkSync variants (`src/zkSync/`) were added after the audit.

## Contracts

| Contract | Purpose |
|---|---|
| `src/Admin.sol` | The plugin, deployed as an EIP-1167 minimal clone. |
| `src/AdminSetup.sol` | Plugin setup: installs and uninstalls the plugin through the `PluginSetupProcessor`. |
| `src/zkSync/AdminZkSync.sol` | Same plugin for zkSync Era, initialized in its constructor (minimal clones do not work on zkSync). |
| `src/zkSync/AdminSetupZkSync.sol` | Plugin setup for zkSync Era (deploys `AdminZkSync` with `new`). |

The plugin is not upgradeable: installations cannot be updated to a newer build. To move to a new build, a DAO uninstalls the plugin and installs the new one.

Deployed addresses and ABIs are published in [artifacts-hub](https://github.com/aragon/artifacts-hub).

## Setup

Requirements: [Foundry](https://getfoundry.sh/) and [just](https://github.com/casey/just).

```shell
git clone https://github.com/aragon/admin-plugin.git
cd admin-plugin
just init <network>   # fetch the git submodules (lib/), create .env from .env.example, select the network (default: mainnet)
just help             # list every recipe (available once the submodules are fetched)
```

`just init` runs `git submodule update --init --recursive`. Run that command yourself if you prefer not to use `just`.

Network settings (RPC, chain ID, OSx and management DAO addresses) come from [just-foundry](https://github.com/aragon/just-foundry) (`lib/just-foundry/networks/<network>.env`). Switch networks with `just switch <network>` and inspect the resolved values with `just env`. Secrets go in `.env` (see `.env.example`) or in `vars` (see `.vars.yaml`).

## Build

```shell
forge build
```

## Test

```shell
just test            # unit, integration and fuzz tests
just test-fork       # fork tests against the active network (requires RPC_URL)
just test-coverage   # HTML coverage report under ./report
```

Layout:

```
test/
├── unit/admin/concrete/<function>/        one folder per function, run for both Admin and AdminZkSync
├── unit/admin/fuzz/
├── unit/adminSetup/concrete/<function>/   run for both AdminSetup and AdminSetupZkSync
├── unit/metadata/                         build metadata vs what the setups decode
├── unit/script/                           deployment scripts
├── integration/concrete/pluginSetup/      install, use and uninstall through a local PluginSetupProcessor
├── fork/                                  live networks
└── utils/                                 constants, mocks, harnesses
```

## Deploy

```shell
just predeploy       # simulate Deploy.s.sol
just deploy          # new network: creates the plugin repo and publishes VERSION_BUILD
just pre-new-version # simulate NewVersion.s.sol
just new-version     # existing repo: deploys the setup, prints the management DAO proposal
```

- Both scripts deploy `AdminSetupZkSync` on zkSync Era (chains 324 and 300) and `AdminSetup` everywhere else.
- `Deploy.s.sol` creates the plugin repo (ENS subdomain `ADMIN_ENS_SUBDOMAIN`: `admin` in production; no ENS name when unset), publishes `PlaceholderSetup` builds below `VERSION_BUILD` so that build numbers match every other network, publishes the setup as `VERSION_BUILD`, and hands ROOT, MAINTAINER and UPGRADE_REPO over to the management DAO.
- `NewVersion.s.sol` deploys the setup and prints the `createVersion` action(s) for `ADMIN_PLUGIN_REPO_ADDRESS`, wrapped in a `createProposal` call for `MANAGEMENT_DAO_MULTISIG_ADDRESS`. Any member of the management DAO multisig submits it.

Both scripts write `artifacts/artifacts-<network>-<timestamp>.json` for artifacts-hub (`just import-plugin <file>` there). On zkSync the setup has no implementation and the artifact omits it. For `NewVersion`, import the artifact only after the proposal has executed.

### Preparing a new build

1. Bump `VERSION_BUILD` in `script/PluginSettings.sol` (and `VERSION_RELEASE` for a new release).
2. Update the files in `script/metadata/`: `build-metadata.json`, `new-version-proposal-metadata.json`, and `release-metadata.json` on a new release.
3. Pin each file with `just ipfs-pin <file>` and paste the `ipfs://` URIs into `script/PluginSettings.sol`. The scripts refuse to run while any of them is empty.

### Deployment checklist

- [ ] I have checked out the official repository on the `main` branch, and `git status` reports no local changes
- [ ] The rest of the ceremony reports the same `git log -n 1` commit hash
- [ ] I have run `just init <network>` and `just env` shows the right network, addresses and deployer
- [ ] `DEPLOYER_KEY` is a fresh wallet that only I operate
- [ ] `ETHERSCAN_API_KEY` is set (when the network uses Etherscan)
- [ ] `VERSION_BUILD` and every metadata URI in `script/PluginSettings.sol` are final
- [ ] `ADMIN_ENS_SUBDOMAIN=admin` (new network only)
- [ ] `just test` runs clean, and `just test-fork` runs clean on the target network
- [ ] `just predeploy` (or `just pre-new-version`) completes without errors
- [ ] `just balance` shows at least 15% more funds than the simulation estimated
- [ ] My machine is on a trusted network and exposes no services
- [ ] I run `just deploy` (or `just new-version`)

### Post deployment checklist

- [ ] The script completed without errors and every contract is verified on the network's explorer
- [ ] The log under `logs/` matches the console output
- [ ] `artifacts/artifacts-<network>-<timestamp>.json` matches the logged addresses, and it was imported into artifacts-hub (after the proposal executed, for `NewVersion`)
- [ ] The plugin repo's ROOT, MAINTAINER and UPGRADE_REPO permissions belong to the management DAO only (`Deploy`)
- [ ] The log, the artifact and `broadcast/<script>/<chain-id>/run-latest.json` are uploaded to the shared location

## zkSync

just-foundry selects `forge-zksync` automatically on zkSync networks (`just switch zksync` or `zksync-sepolia`). The scripts pick `AdminSetupZkSync` there on their own.

## License

AGPL-3.0-or-later, see [LICENSE.md](./LICENSE.md).
