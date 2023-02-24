//npx hardhat run <script>
const hre = require("hardhat");
const fs = require('fs');
async function main() {
    //deploy contract
    const RATE_FEE = 100;
    const Hub = await hre.ethers.getContractFactory("Hub");
    const hub = await Hub.deploy(1000000);
    await hub.deployed();
    const Market = await hre.ethers.getContractFactory("Marketplace");
    const market = await Market.deploy(RATE_FEE, hub.address);
    await market.deployed();
    const Loan = await hre.ethers.getContractFactory("NFTLoan");
    const loan = await Loan.deploy(RATE_FEE, hub.address);
    await loan.deployed();
    const Rental = await hre.ethers.getContractFactory("Rental");
    const rental = await Rental.deploy(RATE_FEE, hub.address);
    await rental.deployed();
    const FungibleToken = await hre.ethers.getContractFactory("FungibleToken");
    const dai = await FungibleToken.deploy("Maker DAI", "DAI");
    await dai.deployed();
    const usdc = await FungibleToken.deploy("Coinbase USD", "USDC");
    await usdc.deployed();
    const usdt = await FungibleToken.deploy("Tether USD", "USDT");
    await usdt.deployed();

    //Add hub child
    await hub.addHubChild(market.address);
    await hub.addHubChild(loan.address);
    await hub.addHubChild(rental.address);
    //Add accept token
    // await hub.addAcceptToken(dai.address);
    // await hub.addAcceptToken(usdc.address);
    // await hub.addAcceptToken(usdt.address);
    const accounts = await hre.ethers.getSigners();

    let dataLog = {
        hub: hub.address,
        loan: loan.address,
        rental: rental.address,
        market: market.address,
        dai: dai.address,
        usdc: usdc.address,
        usdt: usdt.address,
        addr1: accounts[1].address,
        addr2: accounts[2].address,
        addr3: accounts[3].address,
        pnft1: "",
        pnft2: "",
        pnft3: ""
    }
    let data = JSON.stringify(dataLog);
    fs.writeFileSync('config.json', data);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
