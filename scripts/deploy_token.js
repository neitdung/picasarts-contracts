// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

    const FungibleToken = await hre.ethers.getContractFactory("FungibleToken");
    const dai = await FungibleToken.deploy("Maker DAI", "DAI");
    await dai.deployed();
    const usdc = await FungibleToken.deploy("Coinbase USD", "USDC");
    await usdc.deployed();
    const usdt = await FungibleToken.deploy("Tether USD", "USDT");
    await usdt.deployed();
    console.log("FungibleToken: ", dai.address, usdc.address, usdt.address);

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
