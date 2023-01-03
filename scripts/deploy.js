// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {
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
  await hub.addHubChild(market.address);
  await hub.addHubChild(loan.address);
  await hub.addHubChild(rental.address);
  let children = await hub.getHubChild();
  console.log("Hub: ", hub.address);
  console.log("Market: ", market.address);
  console.log("NFTLoan: ", loan.address);
  console.log("Rental: ", rental.address);
  console.log("Hub child: ", children);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
