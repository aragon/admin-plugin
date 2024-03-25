import {Administrator, AdministratorAdminPlugin} from '../../generated/schema';
import {
  Granted,
  Revoked,
} from '../../generated/templates/AdminMembers/PermissionManager';
import {generateAdministratorAdminPluginEntityId} from '../utils/ids';
import {
  generateEntityIdFromAddress,
  generatePluginEntityId,
} from '@aragon/osx-commons-subgraph';
import {dataSource, store} from '@graphprotocol/graph-ts';

export function handleGranted(event: Granted): void {
  if (
    isCorrectEvent(
      event.params.permissionId.toHexString(),
      event.params.where.toHexString()
    )
  ) {
    const pluginAddress = event.params.where;
    const administratorMemberAddress = event.params.who;
    const pluginEntityId = generatePluginEntityId(pluginAddress);
    const administratorMemberEntityId = generateEntityIdFromAddress(
      administratorMemberAddress
    );
    let administrator = Administrator.load(administratorMemberEntityId);
    if (!administrator) {
      administrator = new Administrator(administratorMemberEntityId);
      administrator.address = administratorMemberEntityId;
      administrator.save();
    }

    const administratorAdminMappingId =
      generateAdministratorAdminPluginEntityId(
        pluginAddress,
        administratorMemberAddress
      );
    let administratorPluginMapping = AdministratorAdminPlugin.load(
      administratorAdminMappingId
    );
    if (!administratorPluginMapping) {
      administratorPluginMapping = new AdministratorAdminPlugin(
        administratorAdminMappingId
      );
      administratorPluginMapping.administrator = administratorMemberEntityId;
      administratorPluginMapping.plugin = pluginEntityId;
      administratorPluginMapping.save();
    }
  }
}

export function handleRevoked(event: Revoked): void {
  if (
    isCorrectEvent(
      event.params.permissionId.toHexString(),
      event.params.where.toHexString()
    )
  ) {
    const pluginAddress = event.params.where;
    const administratorMemberAddress = event.params.who;
    const mappingId = generateAdministratorAdminPluginEntityId(
      pluginAddress,
      administratorMemberAddress
    );
    if (AdministratorAdminPlugin.load(mappingId)) {
      store.remove('AdministratorAdminPlugin', mappingId);
    }
  }
}

function isCorrectEvent(permissionId: string, where: string): boolean {
  const context = dataSource.context();
  const requiredPermissionId = context.getString('permissionId');
  if (permissionId == requiredPermissionId) {
    const pluginAddress = context.getString('pluginAddress');
    if (where == pluginAddress) {
      return true;
    }
  }
  return false;
}
