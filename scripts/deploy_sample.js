//npx hardhat run <script>
const hre = require("hardhat");
const config = require("../config.json");
const fs = require('fs');
async function main() {
    //deploy contract
    const Hub = await hre.ethers.getContractFactory("Hub");
    const hub = Hub.attach(config.hub);

    // //Grant role
    const accounts = await hre.ethers.getSigners();
    const artistRole = await hub.ARTIST_ROLE();
    await hub.grantRole(artistRole, accounts[1].address);
    await hub.grantRole(artistRole, accounts[2].address);
    await hub.grantRole(artistRole, accounts[3].address);

    let tx1 = await hub.connect(accounts[1]).createCollection("No Man's Sky", "NMS", "QmUZE7jZEzTqQvqToYTpNK45nDjLrESvGg32uxtk3UfR1r", { value: 1000000 });
    let tx2 = await hub.connect(accounts[2]).createCollection("Random shade of colors", "RSOC", "QmQaVZgHo6hkvtxGFYmceAoEQ8LjMWmiePMYq24FUtN2GF", { value: 1000000 });
    let tx3 =  await hub.connect(accounts[3]).createCollection("Colorful Grid", "CG", "QmXd4EQ8AzkDtbNsyFMadw7WhYPUdr4sruwJbzBJ7FCQEp", { value: 1000000 });

    let receipt1 = await tx1.wait();
    let receipt2 = await tx2.wait();
    let receipt3 = await tx3.wait();

    let eventData1 = receipt1.events?.find((x) => { return x.event == "CollectionCreated" })
    let eventData2 = receipt2.events?.find((x) => { return x.event == "CollectionCreated" })
    let eventData3 = receipt3.events?.find((x) => { return x.event == "CollectionCreated" })
    let dataLog = {
        ...config,
        pnft1: eventData1.args[2],
        pnft2: eventData2.args[2],
        pnft3: eventData3.args[2]
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
