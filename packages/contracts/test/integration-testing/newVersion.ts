import {PluginRepo, AdminSetup, AdminSetup__factory} from '../../typechain';
import {getPluginInfo} from '../../utils/helpers';
import {toHex} from '../../utils/ipfs';
import {PluginRepo__factory} from '@aragon/osx-ethers';
import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {expect} from 'chai';
import {deployments, ethers} from 'hardhat';

async function deployAll() {
  await deployments.fixture(['PluginRepo', 'PlugInVersion']);
}

describe('PluginRepo Deployment', function () {
  let alice: SignerWithAddress;
  let pluginRepo: PluginRepo;

  before(async () => {
    [alice] = await ethers.getSigners();

    // Deploymen should be empty
    expect(await deployments.all()).to.be.empty;

    // Deploy all contracts
    await deployAll();

    // Print info
    console.log(JSON.stringify(getPluginInfo('hardhat')['hardhat'], null, 2));

    pluginRepo = PluginRepo__factory.connect(
      getPluginInfo('hardhat')['hardhat'].address,
      alice
    );
  });

  context('PluginSetup Publication', async () => {
    let setup: AdminSetup;

    before(async () => {
      setup = AdminSetup__factory.connect(
        (await deployments.get('AdminSetup')).address,
        alice
      );
    });
    it('registers the setup', async () => {
      const results = await pluginRepo['getVersion((uint8,uint16))']({
        release: 1,
        build: 1,
      });

      expect(results.pluginSetup).to.equal(setup.address);
      expect(results.buildMetadata).to.equal(
        toHex('ipfs://QmPhswDeTQ46AVbMqnVoGTS7UWjmUN9kjqs7mjdZ3fZg47')
      );
    });
  });
});