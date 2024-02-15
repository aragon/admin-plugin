import {PLUGIN_SETUP_CONTRACT_NAME} from '../../plugin-settings';
import buildMetadata from '../../src/build-metadata.json';
import {AdminSetup, Admin__factory, AdminSetup__factory} from '../../typechain';
import {
  ADMIN_INTERFACE,
  EXECUTE_PROPOSAL_PERMISSION_ID,
} from '../admin-constants';
import {createDaoProxy} from './11_plugin';
import {
  Operation,
  DAO_PERMISSIONS,
  getInterfaceId,
  getNamedTypesFromMetadata,
} from '@aragon/osx-commons-sdk';
import {DAO} from '@aragon/osx-ethers';
import {loadFixture} from '@nomicfoundation/hardhat-network-helpers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {ethers} from 'hardhat';

const abiCoder = ethers.utils.defaultAbiCoder;
const AddressZero = ethers.constants.AddressZero;

describe(PLUGIN_SETUP_CONTRACT_NAME, function () {
  it('does not support the empty interface', async () => {
    const {pluginSetup} = await loadFixture(fixture);
    expect(await pluginSetup.supportsInterface('0xffffffff')).to.be.false;
  });

  it('has an admin plugin implementation base with the correct interface', async () => {
    const {deployer, pluginSetup} = await loadFixture(fixture);

    const admin = Admin__factory.connect(
      await pluginSetup.implementation(),
      deployer
    );
    expect(
      await admin.supportsInterface(getInterfaceId(ADMIN_INTERFACE))
    ).to.be.eq(true);
  });

  describe('prepareInstallation', async () => {
    it('fails if data is empty, or not of minimum length', async () => {
      const {pluginSetup, prepareInstallationInputs, dao} = await loadFixture(
        fixture
      );

      await expect(pluginSetup.prepareInstallation(dao.address, [])).to.be
        .reverted;

      const trimmedData = prepareInstallationInputs.substring(
        0,
        prepareInstallationInputs.length - 2
      );
      await expect(pluginSetup.prepareInstallation(dao.address, trimmedData)).to
        .be.reverted;

      await expect(
        pluginSetup.prepareInstallation(dao.address, prepareInstallationInputs)
      ).not.to.be.reverted;
    });

    it('reverts if encoded address in `_data` is zero', async () => {
      const {pluginSetup, dao} = await loadFixture(fixture);

      const dataWithAddressZero = abiCoder.encode(
        getNamedTypesFromMetadata(
          buildMetadata.pluginSetup.prepareInstallation.inputs
        ),
        [AddressZero]
      );

      await expect(
        pluginSetup.prepareInstallation(dao.address, dataWithAddressZero)
      )
        .to.be.revertedWithCustomError(pluginSetup, 'AdminAddressInvalid')
        .withArgs(AddressZero);
    });

    it('returns the plugin, helpers and permissions', async () => {
      const {alice, pluginSetup, prepareInstallationInputs, dao} =
        await loadFixture(fixture);

      const nonce = await ethers.provider.getTransactionCount(
        pluginSetup.address
      );
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: pluginSetup.address,
        nonce,
      });

      const {
        plugin,
        preparedSetupData: {helpers, permissions},
      } = await pluginSetup.callStatic.prepareInstallation(
        dao.address,
        prepareInstallationInputs
      );

      expect(plugin).to.be.equal(anticipatedPluginAddress);
      expect(helpers.length).to.be.equal(0);
      expect(permissions.length).to.be.equal(2);
      expect(permissions).to.deep.equal([
        [
          Operation.Grant,
          plugin,
          alice.address,
          AddressZero,
          EXECUTE_PROPOSAL_PERMISSION_ID,
        ],
        [
          Operation.Grant,
          dao.address,
          plugin,
          AddressZero,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID,
        ],
      ]);
    });

    it('sets the dao for prepared plugins', async () => {
      const {deployer, pluginSetup, prepareInstallationInputs, dao} =
        await loadFixture(fixture);

      // Check the nonce of the setup contract to obtain the address of the next deployed contract, which will be the plugin clone
      const nonce = await ethers.provider.getTransactionCount(
        pluginSetup.address
      );
      const anticipatedPluginAddress = ethers.utils.getContractAddress({
        from: pluginSetup.address,
        nonce,
      });

      await pluginSetup.prepareInstallation(
        dao.address,
        prepareInstallationInputs
      );

      const adminAddressContract = Admin__factory.connect(
        anticipatedPluginAddress,
        deployer
      );

      expect(await adminAddressContract.dao()).to.be.equal(dao.address);
    });
  });

  describe('prepareUninstallation', async () => {
    it('returns the permissions', async () => {
      const {pluginSetup, prepareUninstallationInputs, dao} = await loadFixture(
        fixture
      );

      const plugin = ethers.Wallet.createRandom().address;

      const permissions = await pluginSetup.callStatic.prepareUninstallation(
        dao.address,
        {
          plugin,
          currentHelpers: [],
          data: prepareUninstallationInputs,
        }
      );

      expect(permissions.length).to.be.equal(1);
      expect(permissions).to.deep.equal([
        [
          Operation.Revoke,
          dao.address,
          plugin,
          AddressZero,
          DAO_PERMISSIONS.EXECUTE_PERMISSION_ID,
        ],
      ]);
    });
  });
});

type FixtureResult = {
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  bob: SignerWithAddress;
  pluginSetup: AdminSetup;
  prepareInstallationInputs: string;
  prepareUninstallationInputs: string;
  dao: DAO;
};

async function fixture(): Promise<FixtureResult> {
  const [deployer, alice, bob] = await ethers.getSigners();

  const dummyMetadata = ethers.utils.hexlify(
    ethers.utils.toUtf8Bytes('0x123456789')
  );
  const dao = await createDaoProxy(deployer, dummyMetadata);
  const pluginSetup = await new AdminSetup__factory(deployer).deploy();

  const prepareInstallationInputs = ethers.utils.defaultAbiCoder.encode(
    getNamedTypesFromMetadata(
      buildMetadata.pluginSetup.prepareInstallation.inputs
    ),
    [alice.address]
  );
  const prepareUninstallationInputs = ethers.utils.defaultAbiCoder.encode(
    getNamedTypesFromMetadata(
      buildMetadata.pluginSetup.prepareUninstallation.inputs
    ),
    []
  );

  return {
    deployer,
    alice,
    bob,
    pluginSetup,
    prepareInstallationInputs,
    prepareUninstallationInputs,
    dao,
  };
}
