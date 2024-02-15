// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/**
 * @title Migration
 *
 * @dev This file imports contracts from
 * - previous versions of `@aragon/osx`
 * - the current or previous versions of @aragon/osx-commons
 * with the purpose of integration and regression testing
 *
 * Each imported contract is aliased as `<contract-name>_<versions_name>` for clarity and to avoid
 * name collisions when the same contract is imported from different versions. This aliasing is only
 * necessary in the context of this Migration.sol file to differentiate between contract versions.
 *
 * After a contract is imported here and the project is compiled, an associated artifact will be
 * generated inside artifacts/@aragon/{version-name}/*,
 * and TypeChain typings will be generated inside typechain/osx-version/{version-name}/* for type-safe interactions with the contract
 * in our tests.
 */

/* solhint-disable no-unused-import */

import {ProxyFactory} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyFactory.sol";

/* solhint-enable no-unused-import */
