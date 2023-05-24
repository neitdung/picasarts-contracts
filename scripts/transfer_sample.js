//npx hardhat run <script>
const hre = require("hardhat");
const config = require("../config.json");
async function main() {
    const FungibleToken = await hre.ethers.getContractFactory("FungibleToken");
    const dai = FungibleToken.attach(config.dai)
    const usdc = FungibleToken.attach(config.usdc)
    const usdt = FungibleToken.attach(config.usdt)

    let transferAmount = hre.ethers.utils.parseEther("1000000");

    await dai.transfer(config.market, transferAmount);
    await usdc.transfer(config.loan, transferAmount);
    await usdt.transfer(config.rental, transferAmount);
    await dai.transfer(config.market, transferAmount);
    await usdc.transfer(config.loan, transferAmount);
    await usdt.transfer(config.rental, transferAmount);
    await dai.transfer(config.market, transferAmount);
    await usdc.transfer(config.loan, transferAmount);
    await usdt.transfer(config.rental, transferAmount);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
