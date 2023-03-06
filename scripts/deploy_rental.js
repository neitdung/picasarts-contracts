const hre = require("hardhat");
const fs = require('fs');
const config = require("../config.json");

async function main() {
    const RATE_FEE = 100;
    const Hub = await hre.ethers.getContractFactory("Hub");
    const hub = await Hub.attach(config.hub);
    const Rental = await hre.ethers.getContractFactory("Rental");
    const rental = await Rental.deploy(RATE_FEE, hub.address);
    await rental.deployed();
    await hub.addHubChild(rental.address);
    await hub.removeHubChild(config.rental);

    let dataLog = {
        ...config,
        rental: rental.address,
    }
    let data = JSON.stringify(dataLog);
    fs.writeFileSync('config.json', data);
    await rental.deployed();
}