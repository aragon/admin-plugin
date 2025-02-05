# Artifacts Package for Admin Plugin

This package is responsible for generating and storing ABIs for smart contracts. It checks out the specified branch, compiles the contracts, and saves the ABIs in the `src/abis/` directory. The package can then be published to NPM for use in other projects.

## Installation

Run the following command to install dependencies:
```sh
yarn install
```

## Usage
###  Generate ABIs
Run:
```sh
yarn generate
```
This will:
1. Check out the `packages/contracts`.
2. Install dependencies.
3. Compile contracts using Hardhat.
4. Generate ABIs using Wagmi.
5. Save the ABIs in `src/abis/`.

## Publishing

To publish the package to NPM, run:
```sh
yarn publish --access public
```
Ensure the package version is updated in `package.json` before publishing.