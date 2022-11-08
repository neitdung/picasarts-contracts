var CollectionFactory = artifacts.require("CollectionFactory");
var Farming = artifacts.require("Farming");
var Marketplace = artifacts.require("Marketplace");
var NFTLoan = artifacts.require("NFTLoan");
var PNFT = artifacts.require("PNFT");
var TestERC20 = artifacts.require("TestERC20");

module.exports = function (deployer) {
    deployer.deploy(CollectionFactory, 1000000);
    deployer.deploy(Farming, 1000);
    deployer.deploy(Marketplace, 1000);
    deployer.deploy(NFTLoan, 100);
    deployer.deploy(PNFT, "Picasarts", "PNFT", "0xD766119a5F4c9Db9823F08034DB770CFe24b4Ac5");
    deployer.deploy(TestERC20, "Maker DAI", "DAI");
    deployer.deploy(TestERC20, "Coinbase USD", "USDC");
    deployer.deploy(TestERC20, "Tether USD", "USDT");
};