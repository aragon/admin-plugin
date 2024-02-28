import buildMetadata from './src/build-metadata.json';
import releaseMetadata from './src/release-metadata.json';
import {VersionTag} from '@aragon/osx-commons-sdk';

export const PLUGIN_CONTRACT_NAME = 'Admin';
export const PLUGIN_SETUP_CONTRACT_NAME = 'AdminSetup';
export const PLUGIN_REPO_ENS_SUBDOMAIN_NAME = 'admin'; // 'admin.plugin.dao.eth'

export const VERSION: VersionTag = {
  release: 1, // Increment this number ONLY if breaking/incompatible changes were made. Updates between releases are NOT possible.
  build: 2, // Increment this number if non-breaking/compatible changes were made. Updates to newer builds are possible.
};

export const METADATA = {
  build: buildMetadata,
  release: releaseMetadata,
};
