require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    bttc: {
      url: "https://pre-rpc.bt.io/",
      accounts: [
        "79a715ccd0da58dadf0511bada461e619ce6e52e11aaf378e962809847e60d80",
        "4c9f21ce0aa8b9807b9a306a49403cc61151f7c2d7bc2df3b209cba714d3c61c",
        "e3d1d6e51b20a8c7aa9c9c25aa27bb55169ab3675ed5ab796bbfa72f0902b4de",
        "f5f9f17baa61ec44ccbe717345115790e0a65d3b15c92d6e0e111082d448ffba"
      ]
    },
    ftm: {
      url: "https://rpc.testnet.fantom.network/",
      accounts: [
        "2d15b230d70eda2ea262f43276a2631dc0b435a1e3bc2af400506660d2ed88c0",
        "d3239fc689c98aa0300fdc72f0472d17c970a837b717615c7e4db700896cbc6a",
        "cab9acd086c0457650d0cdc5b284b03949b9a0fe8199cd5922032552965359af",
        "ac32c3006a406ed0f1581eca6e516bad3e6f8e5b87c2567f0f72d6bca267bc1e"
      ]
    },
    avax: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: [
        "2d15b230d70eda2ea262f43276a2631dc0b435a1e3bc2af400506660d2ed88c0",
        "d3239fc689c98aa0300fdc72f0472d17c970a837b717615c7e4db700896cbc6a",
        "cab9acd086c0457650d0cdc5b284b03949b9a0fe8199cd5922032552965359af",
        "ac32c3006a406ed0f1581eca6e516bad3e6f8e5b87c2567f0f72d6bca267bc1e"
      ]
    }
  },
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
};
