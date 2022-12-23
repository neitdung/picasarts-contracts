const {
    time,
    loadFixture,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");

describe("Rental", function () {
    async function deployNFTFixture() {
        const [owner, addr1, addr2, addr3] = await ethers.getSigners();

        const PNFT = await ethers.getContractFactory("PNFT");
        const Rental = await ethers.getContractFactory("Rental");

        const pnft = await PNFT.deploy("Picasarts NFT Collection", "PNC", owner.address);
        // Deploy rental with fee
        const rental = await Rental.deploy(100);

        await pnft.safeMint(addr1.address, "NFT11", 100);
        await pnft.safeMint(addr1.address, "NFT12", 100);
        await pnft.safeMint(addr2.address, "NFT21", 200);
        await pnft.safeMint(addr2.address, "NFT22", 200);

        return { pnft, rental, owner, addr1, addr2, addr3 };
    }

    describe("Unit Test", function () {
        it("Should deployment with exact owner", async function () {
            const { pnft, owner } = await loadFixture(deployNFTFixture);

            expect(await pnft.owner()).to.equal(owner.address);
        });

        it("Should listing true", async function () {
            const { pnft, rental, addr1 } = await loadFixture(deployNFTFixture);
            await pnft.connect(addr1).approve(rental.address, 0);
            await rental.connect(addr1).list(
                pnft.address,
                0,
                ethers.constants.AddressZero,
                1000,
                100,
                2
            );
            let covenant = await rental.getCovenant(1);
            expect(covenant[0].status).to.equal(1);
            expect(covenant[0].lender).to.equal(addr1.address);
        });
    })
})