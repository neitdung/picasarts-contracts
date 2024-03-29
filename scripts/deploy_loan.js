const hre = require("hardhat");
const fs = require('fs');
const config = require("../config.json");

async function main() {
    const RATE_FEE = 100;
    const Hub = await hre.ethers.getContractFactory("Hub");
    const hub = await Hub.attach(config.hub);
    const Loan = await hre.ethers.getContractFactory("NFTLoan");
    const loan = await Loan.deploy(RATE_FEE, hub.address);
    await loan.deployed();
    await hub.addHubChild(loan.address);
    await hub.removeHubChild(config.loan);

    let dataLog = {
        ...config,
        loan: loan.address,
    }
    console.log(loan.address)

    let data = JSON.stringify(dataLog);
    fs.writeFileSync('config.json', data);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});