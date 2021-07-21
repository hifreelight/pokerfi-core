require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-waffle");

const { mnemonic } = require('./secrets.json');

module.exports = {
    defaultNetwork: "hardhat",
    networks: {
        hardhat: {
        },
        localhost: {
            url: "http://127.0.0.1:8545"
        },
        testnet: {
            url: "https://data-seed-prebsc-1-s2.binance.org:8545",
            chainId: 97,
            gasPrice: 10000000000,
            accounts: { mnemonic: mnemonic }
        },
        mainnet: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            gasPrice: 6000000000,
            accounts: { mnemonic: mnemonic }
        }
    },
    etherscan: {
        apiKey: "U4AN4T2FTQ3CE1XDFYH8HZD8K6Q31Y481V"
    },
    solidity: {
        version: "0.8.0",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    }
};
