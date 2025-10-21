import '@xyrusworx/hardhat-solidity-json';
import '@nomicfoundation/hardhat-toolbox';
import { HardhatUserConfig } from 'hardhat/config';
import '@openzeppelin/hardhat-upgrades';
import 'solidity-coverage';
import '@nomiclabs/hardhat-solhint';
import '@primitivefi/hardhat-dodoc';
import "@parity/hardhat-polkadot";
require('dotenv').config()
const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.17',
        settings: {
          optimizer: {
            enabled: false,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.17"
      }
    ]
  },
  gasReporter: {
    enabled: true,
  },
  dodoc: {
    runOnCompile: false,
    debugMode: true,
    outputDir: "./docgen",
    freshOutput: true,
  },
  resolc: {
    version: "0.3.0",
    compilerSource: "binary",
    settings: {
      emitSourceDebugInfo: true,
      polkaVM: {
        memoryConfig: {
          stackSize: 32768 * 3,
        }
      },
      optimizer: {
        enabled: true,
      },
    }
  },
  networks: {
    hardhat: {
      polkavm: true,
      nodeConfig: {
        nodeBinaryPath: './bin/revive-dev-node',
        rpcPort: 9944,
        dev: true,
      },
      adapterConfig: {
        adapterBinaryPath: './bin/eth-rpc',
        dev: true,
        adapterPort: 8545
      },
    },
    polkadotHubTestnet: {
      polkavm: true,
      url: "https://testnet-passet-hub-eth-rpc.polkadot.io",
      accounts: [process.env.PRIVATE_KEY || '0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133'],
    },
    westend: {
      polkavm: true,
      url: "https://westend-asset-hub-eth-rpc.polkadot.io",
      accounts: [process.env.PRIVATE_KEY || '0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133'],
    },
    assetHub: {
      polkavm: true,
      url: "http://localhost:8545",
      accounts: [process.env.PRIVATE_KEY || '0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133'],
    },
  },
};

export default config;
