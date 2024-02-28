import {PLUGIN_CONTRACT_NAME} from '../../plugin-settings';
import {
  Admin,
  Admin__factory,
  IERC165Upgradeable__factory,
  IMembership__factory,
  IPlugin__factory,
  IProposal__factory,
  IProtocolVersion__factory,
  ProxyFactory__factory,
} from '../../typechain';
import {ProxyCreatedEvent} from '../../typechain/@aragon/osx-commons-contracts/src/utils/deployment/ProxyFactory';
import {ProposalCreatedEvent} from '../../typechain/src/Admin';
import {
  ADMIN_INTERFACE,
  EXECUTE_PROPOSAL_PERMISSION_ID,
} from '../admin-constants';
import {
  findEvent,
  findEventTopicLog,
  proposalIdToBytes32,
  getInterfaceId,
  DAO_PERMISSIONS,
} from '@aragon/osx-commons-sdk';
import {DAO, DAOEvents, DAOStructs, DAO__factory} from '@aragon/osx-ethers';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {ethers} from 'hardhat';

describe(PLUGIN_CONTRACT_NAME, function () {
  describe('initialize', async () => {
    it('reverts if trying to re-initialize', async () => {
      const {initializedPlugin: plugin, dao} = await loadFixture(fixture);
      await expect(plugin.initialize(dao.address)).to.be.revertedWith(
        'Initializable: contract is already initialized'
      );
    });

    it('emits the `MembershipContractAnnounced` event', async () => {
      const {uninitializedPlugin: plugin, dao} = await loadFixture(fixture);
      await expect(plugin.initialize(dao.address))
        .to.emit(
          plugin,
          plugin.interface.getEvent('MembershipContractAnnounced').name
        )
        .withArgs(dao.address);
    });
  });

  describe('membership', async () => {
    it('returns the admins having the `EXECUTE_PROPOSAL_PERMISSION_ID` permission as members', async () => {
      const {
        alice,
        bob,
        initializedPlugin: plugin,
        dao,
      } = await loadFixture(fixture);

      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );

      expect(await plugin.isMember(alice.address)).to.be.true; // Alice has `EXECUTE_PROPOSAL_PERMISSION_ID`
      expect(await plugin.isMember(bob.address)).to.be.false; //  Bob has not
    });
  });

  describe('ERC-165', async () => {
    it('does not support the empty interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      expect(await plugin.supportsInterface('0xffffffff')).to.be.false;
    });

    it('supports the `IERC165Upgradeable` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IERC165Upgradeable__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IPlugin` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IPlugin__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IProtocolVersion` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IProtocolVersion__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IProposal` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IProposal__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `IMembership` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const iface = IMembership__factory.createInterface();
      expect(await plugin.supportsInterface(getInterfaceId(iface))).to.be.true;
    });

    it('supports the `Admin` interface', async () => {
      const {initializedPlugin: plugin} = await loadFixture(fixture);
      const interfaceId = getInterfaceId(ADMIN_INTERFACE);
      expect(await plugin.supportsInterface(interfaceId)).to.be.true;
    });
  });

  describe('execute proposal: ', async () => {
    it('reverts when calling `executeProposal()` if `EXECUTE_PROPOSAL_PERMISSION_ID` is not granted to the admin address', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);

      // Check that the Alice hasn't `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      expect(
        await dao.hasPermission(
          plugin.address,
          alice.address,
          EXECUTE_PROPOSAL_PERMISSION_ID,
          []
        )
      ).to.be.false;

      // Expect Alice's `executeProposal` call to be reverted because she hasn't `EXECUTE_PROPOSAL_PERMISSION_ID` on the Admin plugin
      await expect(
        plugin.connect(alice).executeProposal(dummyMetadata, dummyActions, 0)
      )
        .to.be.revertedWithCustomError(plugin, 'DaoUnauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          alice.address,
          EXECUTE_PROPOSAL_PERMISSION_ID
        );
    });

    it('reverts when calling `executeProposal()` if the `EXECUTE_PERMISSION_ID` on the DAO is not granted to the plugin address', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);

      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );

      // Check that the Admin plugin hasn't `EXECUTE_PERMISSION_ID` on the DAO
      expect(
        await dao.hasPermission(
          plugin.address,
          alice.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID,
          []
        )
      ).to.be.false;

      // Expect Alice's  the `executeProposal` call to be reverted because the Admin plugin hasn't `EXECUTE_PERMISSION_ID` on the DAO
      await expect(
        plugin.connect(alice).executeProposal(dummyMetadata, dummyActions, 0)
      )
        .to.be.revertedWithCustomError(dao, 'Unauthorized')
        .withArgs(
          dao.address,
          plugin.address,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
        );
    });

    it('emits the ProposalCreated event', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);

      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );
      // Grant the Admin plugin the `EXECUTE_PERMISSION_ID` permission on the DAO
      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );

      const currentExpectedProposalId = 0;

      const allowFailureMap = 1;

      const tx = await plugin
        .connect(alice)
        .executeProposal(dummyMetadata, dummyActions, allowFailureMap);

      const eventName = plugin.interface.getEvent('ProposalCreated').name;
      await expect(tx).to.emit(plugin, eventName);
      const event = await findEvent<ProposalCreatedEvent>(tx, eventName);
      expect(event.args.proposalId).to.equal(currentExpectedProposalId);
      expect(event.args.creator).to.equal(alice.address);
      expect(event.args.metadata).to.equal(dummyMetadata);
      expect(event.args.actions.length).to.equal(1);
      expect(event.args.actions[0].to).to.equal(dummyActions[0].to);
      expect(event.args.actions[0].value).to.equal(dummyActions[0].value);
      expect(event.args.actions[0].data).to.equal(dummyActions[0].data);
      expect(event.args.allowFailureMap).to.equal(allowFailureMap);
    });

    it('emits the `ProposalExecuted` event', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);

      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );
      // Grant the Admin plugin the `EXECUTE_PERMISSION_ID` permission on the DAO
      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );

      const currentExpectedProposalId = 0;

      await expect(
        plugin.connect(alice).executeProposal(dummyMetadata, dummyActions, 0)
      )
        .to.emit(plugin, plugin.interface.getEvent('ProposalExecuted').name)
        .withArgs(currentExpectedProposalId);
    });

    it('correctly increments the proposal ID', async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);
      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );
      // Grant the Admin plugin the `EXECUTE_PERMISSION_ID` permission on the DAO
      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );

      const currentExpectedProposalId = 0;

      await plugin
        .connect(alice)
        .executeProposal(dummyMetadata, dummyActions, 0);

      const nextExpectedProposalId = currentExpectedProposalId + 1;

      const tx = await plugin
        .connect(alice)
        .executeProposal(dummyMetadata, dummyActions, 0);

      const eventName = plugin.interface.getEvent('ProposalCreated').name;
      await expect(tx).to.emit(plugin, eventName);

      const event = await findEvent<ProposalCreatedEvent>(tx, eventName);
      expect(event.args.proposalId).to.equal(nextExpectedProposalId);
    });

    it("calls the DAO's execute function using the proposal ID as the call ID", async () => {
      const {
        alice,
        initializedPlugin: plugin,
        dao,
        dummyActions,
        dummyMetadata,
      } = await loadFixture(fixture);

      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );
      // Grant the Admin plugin the `EXECUTE_PERMISSION_ID` permission on the DAO
      await dao.grant(
        dao.address,
        plugin.address,
        DAO_PERMISSIONS.EXECUTE_PERMISSION_ID
      );

      const newPlugin = plugin.connect(alice);
      {
        const proposalId = 0;
        const allowFailureMap = 1;

        const tx = await newPlugin
          .connect(alice)
          .executeProposal(dummyMetadata, dummyActions, allowFailureMap);

        const event = await findEventTopicLog<DAOEvents.ExecutedEvent>(
          tx,
          dao.interface,
          dao.interface.getEvent('Executed').name
        );

        expect(event.args.actor).to.equal(plugin.address);
        expect(event.args.callId).to.equal(proposalIdToBytes32(proposalId));
        expect(event.args.actions.length).to.equal(1);
        expect(event.args.actions[0].to).to.equal(dummyActions[0].to);
        expect(event.args.actions[0].value).to.equal(dummyActions[0].value);
        expect(event.args.actions[0].data).to.equal(dummyActions[0].data);
        // note that failureMap is different than allowFailureMap. See `DAO.sol` for details
        expect(event.args.failureMap).to.equal(0);
      }

      {
        const proposalId = 1;

        const tx = await newPlugin
          .connect(alice)
          .executeProposal(dummyMetadata, dummyActions, 0);

        const event = await findEventTopicLog<DAOEvents.ExecutedEvent>(
          tx,
          dao.interface,
          dao.interface.getEvent('Executed').name
        );
        expect(event.args.callId).to.equal(proposalIdToBytes32(proposalId));
      }
    });
  });
});

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  initializedPlugin: Admin;
  uninitializedPlugin: Admin;
  dao: DAO;
  dummyActions: DAOStructs.ActionStruct[];
  dummyMetadata: string;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob] = await ethers.getSigners();

  const dummyMetadata = ethers.utils.hexlify(
    ethers.utils.toUtf8Bytes('0x123456789')
  );
  const dao = await createDaoProxy(deployer, dummyMetadata);

  const adminPluginImplementation = await new Admin__factory(deployer).deploy();
  const adminProxyFactory = await new ProxyFactory__factory(deployer).deploy(
    adminPluginImplementation.address
  );

  // Create an initialized plugin clone
  const adminPluginInitdata =
    adminPluginImplementation.interface.encodeFunctionData('initialize', [
      dao.address,
    ]);
  const deploymentTx1 = await adminProxyFactory.deployMinimalProxy(
    adminPluginInitdata
  );
  const proxyCreatedEvent1 = await findEvent<ProxyCreatedEvent>(
    deploymentTx1,
    adminProxyFactory.interface.getEvent('ProxyCreated').name
  );
  const initializedPlugin = Admin__factory.connect(
    proxyCreatedEvent1.args.proxy,
    deployer
  );

  const deploymentTx2 = await adminProxyFactory.deployMinimalProxy([]);
  const proxyCreatedEvent2 = await findEvent<ProxyCreatedEvent>(
    deploymentTx2,
    adminProxyFactory.interface.getEvent('ProxyCreated').name
  );
  const uninitializedPlugin = Admin__factory.connect(
    proxyCreatedEvent2.args.proxy,
    deployer
  );

  const dummyActions: DAOStructs.ActionStruct[] = [
    {
      to: deployer.address,
      data: '0x1234',
      value: 0,
    },
  ];

  return {
    deployer,
    alice,
    bob,
    initializedPlugin,
    uninitializedPlugin,
    dao,
    dummyActions,
    dummyMetadata,
  };
}

// TODO Move into OSX commons ?
export async function createDaoProxy(
  deployer: SignerWithAddress,
  dummyMetadata: string
): Promise<DAO> {
  const daoImplementation = await new DAO__factory(deployer).deploy();
  const daoProxyFactory = await new ProxyFactory__factory(deployer).deploy(
    daoImplementation.address
  );

  const daoInitData = daoImplementation.interface.encodeFunctionData(
    'initialize',
    [
      dummyMetadata,
      deployer.address,
      ethers.constants.AddressZero,
      dummyMetadata,
    ]
  );
  const tx = await daoProxyFactory.deployUUPSProxy(daoInitData);
  const event = await findEvent<ProxyCreatedEvent>(
    tx,
    daoProxyFactory.interface.getEvent('ProxyCreated').name
  );
  const dao = DAO__factory.connect(event.args.proxy, deployer);
  return dao;
}
