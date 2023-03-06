const hre = require("hardhat");
const fs = require('fs');
const config = require("../config.json");

async function main() {
    const RATE_FEE = 100;
    const Hub = await hre.ethers.getContractFactory("Hub");
    const hub = await Hub.attach(config.hub);
    const Market = await hre.ethers.getContractFactory("Marketplace");
    const market = await Market.deploy(RATE_FEE, hub.address);
    await market.deployed();
    await hub.addHubChild(market.address);
    await hub.removeHubChild(config.market);

    let dataLog = {
        ...config,
        market: market.address,
    }
    let data = JSON.stringify(dataLog);
    fs.writeFileSync('config.json', data);
    await rental.deployed();
}