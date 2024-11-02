import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.24',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    baseSepolia: {
      url: `https://sepolia.base.org`,
      accounts: [...((process.env.PRIVATE_KEY?.split(',') as string[]) || '')],
      chainId: 84532,
    },
    baseMainnet: {
      url: `https://mainnet.base.org`,
      accounts: [...((process.env.PRIVATE_KEY?.split(',') as string[]) || '')],
      chainId: 8453,
    },
  },
  etherscan: {
    apiKey: {
      baseSepolia: process.env.BASESCAN_API_KEY,
      baseMainnet: process.env.BASESCAN_API_KEY
    },
    customChains: [
      {
          network: "baseSepolia",
          chainId: 84532,
          urls: {
              apiURL: "https://api-sepolia.basescan.org/api",
              browserURL: "https://sepolia.basescan.org/",
          },
      },
      {
        network: "baseMainnet",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
  ],
  },
};

export default config;
