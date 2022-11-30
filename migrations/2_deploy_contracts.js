var Hub = artifacts.require("Hub");
var Marketplace = artifacts.require("Marketplace");
var NFTLoan = artifacts.require("NFTLoan");
var Rental = artifacts.require("Rental");
var PNFT = artifacts.require("PNFT");
var FungibleToken = artifacts.require("FungibleToken");

module.exports = function (deployer) {
    deployer.deploy(Hub, 25);
    deployer.deploy(Rental, 25);
    deployer.deploy(Marketplace, 25);
    deployer.deploy(NFTLoan, 25);
    deployer.deploy(PNFT, "Picasarts", "PNFT", "0xf8805f4FAFd0bef941B9573447005B846DBf1303");
    deployer.deploy(FungibleToken, "Maker DAI", "DAI");
    deployer.deploy(FungibleToken, "Coinbase USD", "USDC");
    deployer.deploy(FungibleToken, "Tether USD", "USDT");
};