const { expect } = require("chai");
const { network, ethers } = require("hardhat");
const { BigNumber, utils }  = require("ethers");
const { writeFile } = require('fs');

describe("Liquidation", function () {
  it("test", async function () {
    await network.provider.request({
        method: "hardhat_reset",
        params: [{
          forking: {
            jsonRpcUrl: process.env.ALCHE_API,
            blockNumber: 11946807,
          }
        }]
      });
    
    const gasPrice = 0;
    const accounts = await ethers.getSigners();
    const liquidator = accounts[0].address;

    const beforeLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const LiquidationOperator = await ethers.getContractFactory("LiquidationOperator");
    const liquidationOperator = await LiquidationOperator.deploy({gasPrice: gasPrice});
    await liquidationOperator.deployed();

    const liquidationTx = await liquidationOperator.operate({gasPrice: gasPrice});
    const liquidationReceipt = await liquidationTx.wait();

    // กรอง Event ของการ Liquidate Target ใหม่ (0x63f603...)
    const expectedLiquidationEvents = liquidationReceipt.logs.filter(v => v.topics[3] ===       '0x00000000000000000000000063f6037d3e9d51ad865056bf7792029803b6eefd');

    expect(expectedLiquidationEvents.length, "no expected liquidation").to.be.above(0);

    const afterLiquidationBalance = BigNumber.from(await hre.network.provider.request({
        method: "eth_getBalance",
        params: [liquidator],
    }));

    const profit = afterLiquidationBalance.sub(beforeLiquidationBalance);
    console.log("Profit", utils.formatEther(profit), "ETH");

    expect(profit.gt(BigNumber.from(0)), "not profitable").to.be.true;
    writeFile('profit.txt', String(utils.formatEther(profit)), function (err) {
        if (err) console.log("failed to write profit.txt: %s", err);
    });
  });
});
