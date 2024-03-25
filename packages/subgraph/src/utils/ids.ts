import {generateEntityIdFromAddress} from '@aragon/osx-commons-subgraph';
import {Address} from '@graphprotocol/graph-ts';

export function generateAdministratorAdminPluginEntityId(
  pluginAddress: Address,
  administratorAddress: Address
): string {
  return [
    generateEntityIdFromAddress(pluginAddress),
    generateEntityIdFromAddress(administratorAddress),
  ].join('_');
}
