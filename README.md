# Admin Plugin [![Hardhat][hardhat-badge]][hardhat] [![License: AGPL v3][license-badge]][license]

[hardhat]: https://hardhat.org/
[hardhat-badge]: https://img.shields.io/badge/Built%20with-Hardhat-FFDB1C.svg
[license]: https://opensource.org/licenses/AGPL-v3
[license-badge]: https://img.shields.io/badge/License-AGPL_v3-blue.svg

## Audit

### v1.2.0

**Halborn**: [audit report](https://github.com/aragon/osx/tree/main/audits/Halborn_AragonOSx_v1_4_Smart_Contract_Security_Assessment_Report_2025_01_03.pdf)

- Commit ID: [546cfa243a5d0726d75158db646573ca2237f570](https://github.com/aragon/admin-plugin/commit/546cfa243a5d0726d75158db646573ca2237f570)
- Started: 2024-11-18
- Finished: 2025-02-13

## Project

The root folder of the repo includes two subfolders:

```markdown
.
├── packages/contracts
│ ├── src
│ ├── deploy
│ ├── test
│ ├── utils
│ ├── ...
│ └── package.json
│
├── packages/subgraph
│ ├── src
│ ├── scripts
│ ├── manifest
│ ├── tests
│ ├── utils
│ ├── ...
│ └── package.json
│
├── ...
└── package.json
```

The root-level `package.json` file contains global `dev-dependencies` for formatting and linting. After installing the dependencies with

```sh
yarn --ignore-scripts
```

you can run the associated [formatting](#formatting) and [linting](#linting) commands.

### Formatting

```sh
yarn prettier:check
```

all `.sol`, `.js`, `.ts`, `.json`, and `.yml` files will be format-checked according to the specifications in `.prettierrc` file.With

```sh
yarn prettier:write
```

the formatting is applied.

### Linting

With

```sh
yarn lint
```

`.sol`, `.js`, and `.ts` files in the subfolders are analyzed with `solhint` and `eslint`, respectively.

### Setting Environment Variables

To be able to work on the contracts, make sure that you have created an `.env` file from the `.env.example` file and put in the API keys for

- [Alchemy](https://www.alchemy.com) that we use as the web3 provider
- [Alchemy Subgraphs](https://www.alchemy.com/subgraphs) that we use as the subgraph provider
- the block explorer that you want to use depending on the networks that you want to deploy to

Before deploying, you MUST also change the default hardhat private key (`PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"`).

## Contracts

This package is located in `packages/contracts`.

### Install Dependencies

```sh
yarn --ignore-scripts
```

### Building

To build the contracts on EVM based networks:

```sh
yarn build
```

On Zksync:

```sh
yarn build:zksync
```

### Testing

To test your contracts on EVM based networks, run

```sh
yarn test
```

On Zksync:

```sh
yarn test:zksync
```

### Linting

Lint the Solidity and TypeScript code all together with

```sh
yarn lint
```

or separately with

```sh
yarn lint:sol
```

and

```sh
yarn lint:ts
```

### Coverage

Generate the code coverage report with

```sh
yarn coverage
```

### Gas Report

See the gas usage per test and average gas per method call with

```sh
REPORT_GAS=true yarn test
```

you can permanently enable the gas reporting by putting the `REPORT_GAS=true` into the `.env` file.

### Deployment

The deploy scripts provided inside `./packages/contracts/deploy` take care of

1. Creating an on-chain [Plugin Repository](https://devs.aragon.org/docs/osx/how-it-works/framework/plugin-management/plugin-repo/) for you through Aragon's factories with an [unique ENS name](https://devs.aragon.org/docs/osx/how-it-works/framework/ens-names).
2. Publishing the first version of your `Plugin` and associated `PluginSetup` contract in your repo from step 1.
3. Upgrade your plugin repository to the latest Aragon OSx protocol version.

Finally, it verifies all contracts on the block explorer of the chosen network.

**You don't need to make changes to the deploy script.** You only have to update the entries in `packages/contracts/plugin-settings.ts` as explained in the template [usage guide](./USAGE_GUIDE.md#contracts).

#### Creating a Plugin Repository & Publishing Your Plugin

Deploy the contracts to the local Hardhat Network (being forked from the network specified in `NETWORK_NAME` in your `.env` file ) with

```sh
yarn deploy --tags CreateRepo,NewVersion
```

This will create a plugin repo and publish the first version (`v1.1`) of your plugin.
By adding the tag `TransferOwnershipToManagmentDao`, the `ROOT_PERMISSION_ID`, `MAINTAINER_PERMISSION_ID`, and
`UPGRADE_REPO_PERMISSION_ID` are granted to the management DAO and revoked from the deployer.
You can do this directly

```sh
yarn deploy --tags CreateRepo,NewVersion,TransferOwnershipToManagmentDao
```

or at a later point by executing

```sh
yarn deploy --tags TransferOwnershipToManagmentDao
```

To deploy the contracts to a production network use the `--network` option, for example

```sh
yarn deploy --network sepolia --tags CreateRepo,NewVersion,TransferOwnershipToManagmentDao,Verification
```

This will create a plugin repo, publish the first version (`v1.1`) of your plugin, transfer permissions to the
management DAO, and lastly verfiy the contracts on sepolia.

If you want to deploy a new version of your plugin afterwards (e.g., `1.2`), simply change the `VERSION` entry in the `packages/contracts/plugin-settings.ts` file and use

```sh
yarn deploy --network sepolia --tags NewVersion,Verification
```

Note, that if the deploying account doesn't own the repo anymore, this will create a `createVersionProposalData-sepolia.json` containing the data for a management DAO signer to create a proposal publishing a new version.

Note, that if you include the `CreateRepo` tag after you've created your plugin repo already, this part of the script will be skipped.

#### Upgrading Your Plugin Repository

Upgrade your plugin repo on the local Hardhat Network (being forked from the network specified in `NETWORK_NAME` in your `.env` file ) with

```sh
yarn deploy --tags UpgradeRepo
```

Upgrade your plugin repo on sepolia with

```sh
yarn deploy --network sepolia --tags UpgradeRepo
```

This will upgrade your plugin repo to the latest Aragon OSx protocol version implementation, which might include new features and security updates.
**For this to work, make sure that you are using the latest version of [this repository](https://github.com/aragon/osx-plugin-template-hardhat) in your fork.**

Note, that if the deploying account doesn't own the repo anymore, this will create a `upgradeRepoProposalData-sepolia.json` containing the data for a management DAO signer to create a proposal upgrading the repo.

If you want to run deployments against zksync, you can use:

```sh
yarn deploy:zksync --network zksyncSepolia --tags ...
yarn deploy:zksync --network zksyncMainnet --tags ...
```

## Subgraph

### Installing

In `packages/subgraph`, first run

```sh
yarn --ignore-scripts
```

which will also run

```sh
yarn postinstall
```

subsequently, to build the ABI in the `imported` folder.

### Building

Build the subgraph and

```sh
yarn build
```

which will first build the contracts (see [Contracts / Building](#building)) with

```
yarn build:contracts
```

second the subgraph manifest with

```sh
yarn build:manifest
```

and finally the subgraph itself with

```
yarn build:subgraph
```

When running `yarn build`, it requires a plugin address, which is obtained from the configuration file located
at `subgraph/manifest/data/<network>.json`, based on the network specified in your `.env` file under the `SUBGRAPH_NETWORK_NAME` variable.
You do not need to provide a plugin address for building or testing purposes, but it becomes necessary when deploying the subgraph.

During development of the subgraph, you might want to clean outdated files that were build, imported, and generated. To do this, run

```sh
yarn clean
```

### Testing

Test the subgraph with

```sh
yarn test
```

### Linting

Lint the TypeScript code with

```sh
yarn lint
```

### Coverage

Generate the code coverage with

```sh
yarn coverage
```

### Deployment

To deploy the subgraph to the subgraph provider, write your intended subgraph name and version into the `SUBGRAPH_NAME` and `SUBGRAPH_VERSION` variables [in the `.env` file that you created in the beginning](environment-variables) and pick a network name `SUBGRAPH_NETWORK_NAME` [being supported by the subgraph provider](https://docs.alchemy.com/reference/supported-subgraph-chains). Remember to place correctly the Plugin address on the network you are going to deploy to, you can do that by adding it on `subgraph/manifest/data/<network>.json`.
Then run

```sh
yarn deploy
```

to deploy the subgraph and check your [Alchemy subgraph dashboard](https://subgraphs.alchemy.com/onboarding) for completion and possible errors.

## License

This project is licensed under AGPL-3.0-or-later.
