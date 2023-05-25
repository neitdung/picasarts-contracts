# Picasarts contracts

## Install
Prerequites: [hardhat](https://hardhat.org/hardhat-runner/docs/getting-started#overview) 

- Clone repository
- Install modules: ```npm install```
- Compile contracts: ```npx hardhat conpile```
- Config network in file: ```hardhat.config.js```
- Deploy contracts: ```npx hardhat run --network <network> scripts/deploy_all.js```
- Get file ```config.json``` and all files in folder ```abis```

## Design

Picasarts has 1 governance contract (Hub) and 3 feature contracts (Marketplace, Loan and Rental). For handle logic of feature contracts and futher extending contract, this is design of them:

![Smart contracts design](../imgs/main-sc.png)

Those also use same a NFT standard contract called PNFT extend from ERC-721, ERC-2981 and ERC-4907. This is not required, you can create new PNFT contract by Hub or just import simple ERC-721 contract that extend Ownable contract but I encourage you use this contract for able using full product features.

![PNFT](docs/imgs/pnft.png)

## Use cases and flow

![All usecase](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/all-uc.png)

### Hub

![Hub](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/hub-uc.png)

### Marketplace

- Use cases:
![Market use cases](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/market-uc.png)
- Flow:
![Market flow](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/market-fl.png)

### Loan

- Use cases:
![Loan use cases](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/loan-uc.png)
- Flow:
![Loan flow](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/loan-fl.png)
- Explain status after each action:
![Loan explain](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/loan-expl.png)

### Rental

- Use cases:
![Rental use cases](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/rent-uc.png)
- Flow:
![Rental flow](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/rent-fl.png)
- Calculate amount can withdraw:
![Rental explain](https://raw.githubusercontent.com/neitdung/picasarts-docs/main/imgs/rent-expl.png)

More documents about project: [picasarts-docs](https://github.com/neitdung/picasarts-docs)

