import hre from "hardhat";

async function main() {
    
    // 代理合约地址
    const proxyAddress = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9";
    
    // 连接到升级后的合约
    const connection = await hre.network.connect();
    const ethers = connection.ethers;
    const metaNodeStakeV2 = await ethers.getContractAt("MetaNodeStakeV2", proxyAddress);
    
    // 调用新的version函数
    const version = await metaNodeStakeV2.version();
    console.log("MetaNodeStake version:", version);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
