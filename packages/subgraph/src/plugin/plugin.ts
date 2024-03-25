import {
  Action,
  AdministratorAdminPlugin,
  AdminProposal,
  Administrator,
} from '../../generated/schema';
import {AdminMembers} from '../../generated/templates';
import {
  MembershipContractAnnounced,
  ProposalCreated,
  ProposalExecuted,
} from '../../generated/templates/Plugin/Admin';
import {EXECUTE_PROPOSAL_PERMISSION_HASH} from '../utils/constants';
import {generateAdministratorAdminPluginEntityId} from '../utils/ids';
import {
  generateActionEntityId,
  generatePluginEntityId,
  generateProposalEntityId,
} from '@aragon/osx-commons-subgraph';
import {Address, dataSource, DataSourceContext} from '@graphprotocol/graph-ts';

export function handleProposalCreated(event: ProposalCreated): void {
  const context = dataSource.context();
  const daoAddress = context.getString('daoAddress');
  const metadata = event.params.metadata.toString();
  _handleProposalCreated(event, daoAddress, metadata);
}

export function _handleProposalCreated(
  event: ProposalCreated,
  daoAddress: string,
  metadata: string
): void {
  const pluginProposalId = event.params.proposalId;
  const pluginAddress = event.address;
  const pluginEntityId = generatePluginEntityId(pluginAddress);
  const proposalEntityId = generateProposalEntityId(
    pluginAddress,
    pluginProposalId
  );
  const administratorAddress = event.params.creator;

  const proposalEntity = new AdminProposal(proposalEntityId);
  proposalEntity.daoAddress = Address.fromHexString(daoAddress);
  proposalEntity.plugin = pluginEntityId;
  proposalEntity.pluginProposalId = pluginProposalId;
  proposalEntity.creator = administratorAddress;
  proposalEntity.metadata = metadata;
  proposalEntity.executed = false;
  proposalEntity.createdAt = event.block.timestamp;
  proposalEntity.startDate = event.params.startDate;
  proposalEntity.endDate = event.params.endDate;
  proposalEntity.administrator = administratorAddress.toHexString();
  proposalEntity.allowFailureMap = event.params.allowFailureMap;
  const administratorEntityId = generateAdministratorAdminPluginEntityId(
    administratorAddress,
    pluginAddress
  );
  let adminMemberEntity = AdministratorAdminPlugin.load(administratorEntityId);
  if (!adminMemberEntity) {
    adminMemberEntity = new AdministratorAdminPlugin(administratorEntityId);
    adminMemberEntity.administrator = administratorAddress.toHexString();
    adminMemberEntity.plugin = pluginEntityId;
    adminMemberEntity.save();
  }
  let administratorEntity = Administrator.load(
    administratorAddress.toHexString()
  );
  if (!administratorEntity) {
    administratorEntity = new Administrator(administratorAddress.toHexString());
    administratorEntity.address = administratorAddress.toHexString();
    administratorEntity.save();
  }

  // actions
  const actions = event.params.actions;
  for (let index = 0; index < actions.length; index++) {
    const action = actions[index];

    const actionEntityId = generateActionEntityId(proposalEntityId, index);
    const actionEntity = new Action(actionEntityId);
    actionEntity.to = action.to;
    actionEntity.value = action.value;
    actionEntity.data = action.data;
    actionEntity.daoAddress = Address.fromHexString(daoAddress);
    actionEntity.proposal = proposalEntityId;
    actionEntity.save();
  }

  proposalEntity.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  const pluginProposalId = event.params.proposalId;
  const proposalEntityId = generateProposalEntityId(
    event.address,
    pluginProposalId
  );

  const proposalEntity = AdminProposal.load(proposalEntityId);
  if (proposalEntity) {
    proposalEntity.executed = true;
    proposalEntity.executionTxHash = event.transaction.hash;
    proposalEntity.save();
  }
}

export function handleMembershipContractAnnounced(
  event: MembershipContractAnnounced
): void {
  const context = new DataSourceContext();
  context.setString('pluginAddress', event.address.toHexString());
  context.setString('permissionId', EXECUTE_PROPOSAL_PERMISSION_HASH);
  AdminMembers.createWithContext(event.params.definingContract, context);
}
