import hre from "hardhat";
import MetaNodeStakeModule from "../ignition/modules/MetaNodeStake.js";

async function main() {
    const connection = await hre.network.connect();
    const ethers = connection.ethers;
    const currentBlock = await ethers.provider.getBlockNumber();
    console.log("Current block number:", currentBlock);

    const parameters = {
        metaNodePerBlock: ethers.parseEther("10"), 
        startBlock: currentBlock + 10, // 从当前区块的10个区块后开始挖矿
        durationDays: 365, // 持续时间为365天
        endBlock: currentBlock + 10 + Math.floor((365 * 24 * 60 * 60) / 12), // 计算结束区块
    };

    console.log("Deployment parameters:", parameters);

    const { metaNodeToken, proxy, metaNodeStake } = await connection.ignition.deploy(MetaNodeStakeModule, {
        parameters: { MetaNodeStakeModule: parameters },
    });

    console.log("MetaNodeToken deployed to:", await metaNodeToken.getAddress());
    console.log("Proxy deployed to:", await proxy.getAddress());
    console.log("MetaNodeStake deployed to:", await metaNodeStake.getAddress());
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});