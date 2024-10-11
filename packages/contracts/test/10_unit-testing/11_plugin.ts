import {createDaoProxy} from '../20_integration-testing/test-helpers';
import {PLUGIN_CONTRACT_NAME} from '../../plugin-settings';
import {
  Admin,
  Admin__factory,
  CustomExecutorMock__factory,
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
  Operation,
  SET_TARGET_CONFIG_PERMISSION_ID,
  TargetConfig,
} from '../admin-constants';
import {
  findEvent,
  findEventTopicLog,
  getInterfaceId,
  DAO_PERMISSIONS,
} from '@aragon/osx-commons-sdk';
import {DAO, DAOEvents, DAOStructs} from '@aragon/osx-ethers';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {BigNumber} from 'ethers';
import {defaultAbiCoder, keccak256} from 'ethers/lib/utils';
import {ethers} from 'hardhat';

let chainId: number;

async function createProposalId(
  pluginAddress: string,
  actions: DAOStructs.ActionStruct[],
  metadata: string
): Promise<BigNumber> {
  const blockNumber = (await ethers.provider.getBlock('latest')).number;
  const salt = keccak256(
    defaultAbiCoder.encode(
      ['tuple(address to,uint256 value,bytes data)[]', 'bytes'],
      [actions, metadata]
    )
  );
  return BigNumber.from(
    keccak256(
      defaultAbiCoder.encode(
        ['uint256', 'uint256', 'address', 'bytes32'],
        [chainId, blockNumber + 1, pluginAddress, salt]
      )
    )
  );
}

describe(PLUGIN_CONTRACT_NAME, function () {
  before(async () => {
    chainId = (await ethers.provider.getNetwork()).chainId;
  });

  describe('initialize', async () => {
    it('reverts if trying to re-initialize', async () => {
      const {
        initializedPlugin: plugin,
        dao,
        targetConfig,
      } = await loadFixture(fixture);
      await expect(
        plugin.initialize(dao.address, targetConfig)
      ).to.be.revertedWith('Initializable: contract is already initialized');
    });

    it('emits the `MembershipContractAnnounced` event', async () => {
      const {
        uninitializedPlugin: plugin,
        dao,
        targetConfig,
      } = await loadFixture(fixture);
      await expect(plugin.initialize(dao.address, targetConfig))
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
    it('reverts when calling `execute()` if `EXECUTE_PROPOSAL_PERMISSION_ID` is not granted to the admin address', async () => {
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

      // Expect Alice's `execute` call to be reverted because she hasn't `EXECUTE_PROPOSAL_PERMISSION_ID` on the Admin plugin
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

    it('reverts when calling `execute()` if the `EXECUTE_PERMISSION_ID` on the DAO is not granted to the plugin address', async () => {
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

      // Expect Alice's  the `execute` call to be reverted because the Admin plugin hasn't `EXECUTE_PERMISSION_ID` on the DAO
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

      const currentExpectedProposalId = await createProposalId(
        plugin.address,
        dummyActions,
        dummyMetadata
      );

      const allowFailureMap = 1;

      const tx = await plugin
        .connect(alice)
        .executeProposal(dummyMetadata, dummyActions, allowFailureMap);

      const eventName = plugin.interface.getEvent('ProposalCreated').name;
      await expect(tx).to.emit(plugin, eventName);
      const event = findEvent<ProposalCreatedEvent>(await tx.wait(), eventName);
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

      const currentExpectedProposalId = await createProposalId(
        plugin.address,
        dummyActions,
        dummyMetadata
      );

      await expect(
        plugin.connect(alice).executeProposal(dummyMetadata, dummyActions, 0)
      )
        .to.emit(plugin, plugin.interface.getEvent('ProposalExecuted').name)
        .withArgs(currentExpectedProposalId);
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
        const proposalId = await createProposalId(
          plugin.address,
          dummyActions,
          dummyMetadata
        );

        const allowFailureMap = 1;

        const tx = await newPlugin
          .connect(alice)
          .executeProposal(dummyMetadata, dummyActions, allowFailureMap);

        const event = findEventTopicLog<DAOEvents.ExecutedEvent>(
          await tx.wait(),
          dao.interface,
          dao.interface.getEvent('Executed').name
        );

        expect(event.args.actor).to.equal(plugin.address);
        expect(event.args.callId).to.equal(proposalId);
        expect(event.args.actions.length).to.equal(1);
        expect(event.args.actions[0].to).to.equal(dummyActions[0].to);
        expect(event.args.actions[0].value).to.equal(dummyActions[0].value);
        expect(event.args.actions[0].data).to.equal(dummyActions[0].data);
        // note that failureMap is different than allowFailureMap. See `DAO.sol` for details
        expect(event.args.failureMap).to.equal(0);
      }

      {
        const newMetadata = dummyMetadata + '11';

        const proposalId = await createProposalId(
          plugin.address,
          dummyActions,
          newMetadata
        );

        const tx = await newPlugin
          .connect(alice)
          .executeProposal(newMetadata, dummyActions, 0);

        const event = findEventTopicLog<DAOEvents.ExecutedEvent>(
          await tx.wait(),
          dao.interface,
          dao.interface.getEvent('Executed').name
        );
        expect(event.args.callId).to.equal(proposalId);
      }
    });

    it('calls executeProposal within createProposal', async () => {
      const {
        alice,
        dummyMetadata,
        dummyActions,
        dao,
        initializedPlugin: plugin,
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

      await expect(
        plugin
          .connect(alice)
          .createProposal(dummyMetadata, dummyActions, 0, 0, '0x')
      ).to.emit(plugin, 'ProposalExecuted');
    });

    it('executes target with delegate call', async () => {
      const {
        alice,
        bob,
        dummyMetadata,
        dummyActions,
        deployer,
        dao,
        initializedPlugin: plugin,
      } = await loadFixture(fixture);

      const executorFactory = new CustomExecutorMock__factory(deployer);
      const executor = await executorFactory.deploy();

      const abiA = CustomExecutorMock__factory.abi;
      const abiB = Admin__factory.abi;
      // @ts-ignore
      const mergedABI = abiA.concat(abiB);

      await dao.grant(
        plugin.address,
        deployer.address,
        SET_TARGET_CONFIG_PERMISSION_ID
      );

      await plugin.connect(deployer).setTargetConfig({
        target: executor.address,
        operation: Operation.delegatecall,
      });

      const pluginMerged = (await ethers.getContractAt(
        mergedABI,
        plugin.address
      )) as Admin;

      // Grant Alice the `EXECUTE_PROPOSAL_PERMISSION_ID` permission on the Admin plugin
      await dao.grant(
        plugin.address,
        alice.address,
        EXECUTE_PROPOSAL_PERMISSION_ID
      );

      await expect(
        plugin.connect(alice).executeProposal(dummyMetadata, dummyActions, 1)
      )
        .to.emit(pluginMerged, 'ExecutedCustom')
        .to.emit(pluginMerged, 'ProposalExecuted');
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
  targetConfig: TargetConfig;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob] = await ethers.getSigners();
  const dummyMetadata = '0x12345678';
  const dao = await createDaoProxy(deployer, dummyMetadata);

  const adminPluginImplementation = await new Admin__factory(deployer).deploy();
  const adminProxyFactory = await new ProxyFactory__factory(deployer).deploy(
    adminPluginImplementation.address
  );

  const targetConfig: TargetConfig = {
    operation: Operation.call,
    target: dao.address,
  };

  // Create an initialized plugin clone
  const adminPluginInitdata =
    adminPluginImplementation.interface.encodeFunctionData('initialize', [
      dao.address,
      targetConfig,
    ]);
  const deploymentTx1 = await adminProxyFactory.deployMinimalProxy(
    adminPluginInitdata
  );
  const proxyCreatedEvent1 = await findEvent<ProxyCreatedEvent>(
    await deploymentTx1.wait(),
    adminProxyFactory.interface.getEvent('ProxyCreated').name
  );
  const initializedPlugin = Admin__factory.connect(
    proxyCreatedEvent1.args.proxy,
    deployer
  );

  const deploymentTx2 = await adminProxyFactory.deployMinimalProxy([]);
  const proxyCreatedEvent2 = await findEvent<ProxyCreatedEvent>(
    await deploymentTx2.wait(),
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
    targetConfig,
  };
}
