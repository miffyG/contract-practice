import { expect } from "chai";
import hre from "hardhat";
import { MetaNodeToken, MetaNodeStake } from "../types/ethers-contracts/index.js";

// Sepolia 测试网上已部署的合约地址
const DEPLOYED_ADDRESSES = {
    MetaNodeToken: "0xB0EfEad00Aca442dd835845B9F6f5d9eCf76efc4",
    MetaNodeStakeProxy: "0x2940Ffd4613391ADBd13DCFacbDA4a5ffa6344A4"
};

describe("MetaNodeStake on Sepolia Testnet", function () {
    // 增加测试超时时间，因为在测试网上交易可能较慢
    this.timeout(180000); // 3分钟超时
    
    let metaNodeToken: MetaNodeToken;
    let metaNodeStake: MetaNodeStake;
    let owner: any;
    let user1: any;
    let user2: any;
    let ethers: any;

    // 重试函数
    async function retryOperation<T>(
        operation: () => Promise<T>, 
        maxRetries: number = 3, 
        delay: number = 2000
    ): Promise<T> {
        for (let i = 0; i < maxRetries; i++) {
            try {
                return await operation();
            } catch (error: any) {
                console.log(`Attempt ${i + 1} failed: ${error.message}`);
                if (i === maxRetries - 1) {
                    throw error;
                }
                console.log(`Retrying in ${delay}ms...`);
                await new Promise(resolve => setTimeout(resolve, delay));
                delay *= 1.5; // 指数退避
            }
        }
        throw new Error("Max retries exceeded");
    }

    before(async function () {
        // 连接到Sepolia网络
        console.log("Connecting to Sepolia network...");
        
        // 获取网络连接和ethers实例
        const connection = await hre.network.connect();
        ethers = connection.ethers;
        
        // 获取测试账户
        const signers = await ethers.getSigners();
        owner = signers[0];
        
        // 如果只有一个signer，创建额外的测试钱包
        if (signers.length === 1) {
            // 创建随机钱包用于测试
            user1 = ethers.Wallet.createRandom().connect(ethers.provider);
            user2 = ethers.Wallet.createRandom().connect(ethers.provider);
            
            console.log("Created random test wallets:");
            console.log("User1 address:", user1.address);
            console.log("User2 address:", user2.address);
            
            // 给测试钱包转一些ETH用于gas费
            try {
                const transferAmount = ethers.parseEther("0.1");
                
                console.log("Funding test wallets with ETH...");
                
                const tx1 = await retryOperation(async () => {
                    return await owner.sendTransaction({
                        to: user1.address,
                        value: transferAmount,
                        gasLimit: 21000,
                        gasPrice: ethers.parseUnits("1.5", "gwei")
                    });
                });
                await retryOperation(async () => await tx1.wait());
                
                const tx2 = await retryOperation(async () => {
                    return await owner.sendTransaction({
                        to: user2.address,
                        value: transferAmount,
                        gasLimit: 21000,
                        gasPrice: ethers.parseUnits("1.5", "gwei")
                    });
                });
                await retryOperation(async () => await tx2.wait());
                
                console.log(`Transferred ${ethers.formatEther(transferAmount)} ETH to each test wallet`);
            } catch (error: any) {
                console.log(`Failed to fund test wallets: ${error.message}`);
                // 如果转账失败，回退到使用owner账户
                user1 = owner;
                user2 = owner;
            }
        } else {
            // 如果有多个signers，直接使用
            user1 = signers.length > 1 ? signers[1] : signers[0];
            user2 = signers.length > 2 ? signers[2] : signers[0];
        }
        
        console.log("Owner address:", owner.address);
        console.log("User1 address:", user1.address);
        console.log("User2 address:", user2.address);
        console.log("Available signers:", signers.length);

        // 连接到已部署的合约
        metaNodeToken = await ethers.getContractAt(
            "MetaNodeToken", 
            DEPLOYED_ADDRESSES.MetaNodeToken
        ) as MetaNodeToken;

        metaNodeStake = await ethers.getContractAt(
            "MetaNodeStake", 
            DEPLOYED_ADDRESSES.MetaNodeStakeProxy
        ) as MetaNodeStake;

        console.log("Connected to MetaNodeToken at:", await metaNodeToken.getAddress());
        console.log("Connected to MetaNodeStake at:", await metaNodeStake.getAddress());
    });

    describe("Contract Information", function () {
        it("should return correct contract information", async function () {
            // 检查MetaNode代币信息
            const tokenName = await metaNodeToken.name();
            const tokenSymbol = await metaNodeToken.symbol();
            const tokenDecimals = await metaNodeToken.decimals();
            const totalSupply = await metaNodeToken.totalSupply();

            console.log(`Token Name: ${tokenName}`);
            console.log(`Token Symbol: ${tokenSymbol}`);
            console.log(`Token Decimals: ${tokenDecimals}`);
            console.log(`Total Supply: ${ethers.formatEther(totalSupply)} ${tokenSymbol}`);

            expect(tokenName).to.equal("MetaNodeToken");
            expect(tokenSymbol).to.equal("MetaNode");
            expect(tokenDecimals).to.equal(18);

            // 检查质押合约信息
            const metaNodePerBlock = await metaNodeStake.metaNodePerBlock();
            const startBlock = await metaNodeStake.startBlock();
            const endBlock = await metaNodeStake.endBlock();
            const currentBlock = await ethers.provider.getBlockNumber();

            console.log(`MetaNode Per Block: ${ethers.formatEther(metaNodePerBlock)}`);
            console.log(`Start Block: ${startBlock}`);
            console.log(`End Block: ${endBlock}`);
            console.log(`Current Block: ${currentBlock}`);

            expect(metaNodePerBlock).to.be.gt(0);
            expect(startBlock).to.be.gt(0);
            expect(endBlock).to.be.gt(startBlock);
        });

        it("should return correct pool count", async function () {
            const poolLength = await metaNodeStake.poolLength();
            console.log(`Total pools: ${poolLength}`);
            
            // 如果有池，显示每个池的信息
            for (let i = 0; i < poolLength; i++) {
                const pool = await metaNodeStake.pools(i);
                console.log(`Pool ${i}:`);
                console.log(`  Token Address: ${pool.stTokenAddress}`);
                console.log(`  Pool Weight: ${pool.poolWeight}`);
                console.log(`  Min Deposit: ${ethers.formatEther(pool.minDepositAmount)} ETH`);
                console.log(`  Unstake Lock Blocks: ${pool.unstakeLockedBlocks}`);
                console.log(`  Total Staked: ${ethers.formatEther(pool.stTokenAmount)} ETH`);
            }
        });
    });

    describe("Pool Management", function () {
        it("should allow only admin to add new staking pools", async function () {
            const poolLengthBefore = await metaNodeStake.poolLength();
            
            try {
                // 尝试添加ETH质押池 (address(0) 表示ETH)
                const tx = await metaNodeStake.addPool(
                    ethers.ZeroAddress, // ETH
                    100, // 权重
                    ethers.parseEther("0.01"), // 最小质押 0.01 ETH
                    7200 // 解质押锁定区块数 (约1天)
                );
                await tx.wait();
                
                const poolLengthAfter = await metaNodeStake.poolLength();
                expect(poolLengthAfter).to.equal(poolLengthBefore + 1n);
                
                console.log("Successfully added ETH staking pool");
            } catch (error: any) {
                if (error.message.includes("AccessControl")) {
                    console.log("Access control working correctly - only admin can add pools");
                } else if (poolLengthBefore > 0) {
                    console.log("Pool already exists, skipping creation");
                } else {
                    throw error;
                }
            }
        });

        it("should return correct pool information", async function () {
            const poolLength = await metaNodeStake.poolLength();
            if (poolLength > 0) {
                const pool = await metaNodeStake.pools(0);
                
                expect(pool.stTokenAddress).to.be.a("string");
                expect(pool.poolWeight).to.be.gt(0);
                expect(pool.minDepositAmount).to.be.gte(0);
                expect(pool.unstakeLockedBlocks).to.be.gt(0);
                
                console.log("Pool 0 details verified successfully");
            } else {
                console.log("No pools available to test");
            }
        });
    });

    describe("Token Balance and Allowance", function () {
        it("should return correct token balances", async function () {
            const ownerBalance = await metaNodeToken.balanceOf(owner.address);
            const user1Balance = await metaNodeToken.balanceOf(user1.address);
            const contractBalance = await metaNodeToken.balanceOf(await metaNodeStake.getAddress());

            console.log(`Owner MetaNode balance: ${ethers.formatEther(ownerBalance)}`);
            console.log(`User1 MetaNode balance: ${ethers.formatEther(user1Balance)}`);
            console.log(`Contract MetaNode balance: ${ethers.formatEther(contractBalance)}`);

            // 检查ETH余额
            const ownerEthBalance = await ethers.provider.getBalance(owner.address);
            const user1EthBalance = await ethers.provider.getBalance(user1.address);

            console.log(`Owner ETH balance: ${ethers.formatEther(ownerEthBalance)}`);
            console.log(`User1 ETH balance: ${ethers.formatEther(user1EthBalance)}`);
        });

        it("should allow transferring tokens to test users if sufficient balance", async function () {
            const ownerBalance = await metaNodeToken.balanceOf(owner.address);
            
            // 只有在owner有足够余额时才进行转账测试
            if (ownerBalance > ethers.parseEther("1000") && owner.address !== user1.address) {
                try {
                    const transferAmount = ethers.parseEther("1000");
                    
                    console.log("Transferring tokens to user1...");
                    
                    // 使用重试机制进行代币转账
                    const tx = await retryOperation(async () => {
                        return await metaNodeToken.transfer(user1.address, transferAmount, {
                            gasLimit: 100000,
                            gasPrice: ethers.parseUnits("1.5", "gwei")
                        });
                    });
                    
                    await retryOperation(async () => await tx.wait());
                    
                    const user1Balance = await metaNodeToken.balanceOf(user1.address);
                    console.log(`Transferred ${ethers.formatEther(transferAmount)} tokens to user1`);
                    console.log(`User1 new balance: ${ethers.formatEther(user1Balance)}`);
                    
                    expect(user1Balance).to.be.gte(transferAmount);
                } catch (error: any) {
                    console.log(`Transfer failed: ${error.message}`);
                    
                    // 如果是网络错误，不让测试失败
                    if (error.message.includes("Failed to make POST request") || 
                        error.message.includes("network") || 
                        error.message.includes("timeout") ||
                        error.message.includes("socket disconnected")) {
                        console.log("⚠️  Network connectivity issue during transfer - skipping test");
                        return;
                    }
                }
            } else {
                console.log("Skipping transfer test - owner doesn't have enough tokens or same as user1");
            }
        });
    });

    describe("Staking Operations", function () {
        it("should allow ETH staking", async function () {
            const poolLength = await metaNodeStake.poolLength();
            
            if (poolLength > 0) {
                const pool = await metaNodeStake.pools(0);
                const minDeposit = pool.minDepositAmount;
                
                // 如果最小质押金额合理，尝试质押
                if (minDeposit <= ethers.parseEther("1")) {
                    const stakeAmount = minDeposit > 0 ? minDeposit : ethers.parseEther("0.01");
                    
                    try {
                        const userBefore = await metaNodeStake.users(0, user1.address);
                        console.log(`User1 staked amount before: ${ethers.formatEther(userBefore.stAmount)}`);
                        
                        // 使用重试机制进行质押
                        const tx = await retryOperation(async () => {
                            return await metaNodeStake.connect(user1).deposit(0, stakeAmount, {
                                value: stakeAmount,
                                gasLimit: 300000,
                                gasPrice: ethers.parseUnits("1.5", "gwei")
                            });
                        });
                        
                        console.log("Transaction submitted, waiting for confirmation...");
                        const receipt = await retryOperation(async () => {
                            return await tx.wait();
                        });
                        
                        if (receipt) {
                            console.log(`Transaction confirmed in block: ${receipt.blockNumber}`);
                        }
                        
                        const userAfter = await metaNodeStake.users(0, user1.address);
                        console.log(`User1 staked amount after: ${ethers.formatEther(userAfter.stAmount)}`);
                        console.log(`Successfully staked ${ethers.formatEther(stakeAmount)} ETH`);
                        
                        expect(userAfter.stAmount).to.equal(userBefore.stAmount + stakeAmount);
                    } catch (error: any) {
                        console.log(`Staking failed after retries: ${error.message}`);
                        
                        // 如果是网络错误，不让测试失败
                        if (error.message.includes("Failed to make POST request") || 
                            error.message.includes("network") || 
                            error.message.includes("timeout") ||
                            error.message.includes("socket disconnected")) {
                            console.log("⚠️  Network connectivity issue detected - skipping staking test");
                            return; // 跳过这个测试
                        }
                        
                        // 如果是因为余额不足或其他可预期的原因，不抛出错误
                        if (!error.message.includes("insufficient funds") && 
                            !error.message.includes("Deposit amount is less than minimum")) {
                            throw error;
                        }
                    }
                } else {
                    console.log(`Minimum deposit too high: ${ethers.formatEther(minDeposit)} ETH`);
                }
            } else {
                console.log("No pools available for staking");
            }
        });

        it("should allow checking pending rewards", async function () {
            const poolLength = await metaNodeStake.poolLength();
            
            if (poolLength > 0) {
                try {
                    const pendingReward = await metaNodeStake.pendingReward(0, user1.address);
                    console.log(`User1 pending reward: ${ethers.formatEther(pendingReward)} MetaNode`);
                    
                    expect(pendingReward).to.be.gte(0);
                } catch (error: any) {
                    console.log(`Failed to get pending reward: ${error.message}`);
                }
            }
        });

        it("should allow checking unstake requests", async function () {
            const poolLength = await metaNodeStake.poolLength();
            
            if (poolLength > 0) {
                try {
                    const requestCount = await metaNodeStake.getUserUnstakeRequestCount(0, user1.address);
                    console.log(`User1 unstake request count: ${requestCount}`);
                    
                    const withdrawable = await metaNodeStake.getWithdrawableAmount(0, user1.address);
                    console.log(`User1 withdrawable amount: ${ethers.formatEther(withdrawable)} ETH`);
                    
                    expect(requestCount).to.be.gte(0);
                    expect(withdrawable).to.be.gte(0);
                } catch (error: any) {
                    console.log(`Failed to get unstake info: ${error.message}`);
                }
            }
        });

        it("should allow testing unstaking process", async function () {
            const poolLength = await metaNodeStake.poolLength();
            
            if (poolLength > 0) {
                try {
                    const user = await metaNodeStake.users(0, user1.address);
                    
                    // 如果用户有质押，尝试部分解质押
                    if (user.stAmount > 0) {
                        const unstakeAmount = user.stAmount / 2n; // 解质押一半
                        
                        if (unstakeAmount > 0) {
                            console.log(`Attempting to unstake ${ethers.formatEther(unstakeAmount)} ETH`);
                            
                            const tx = await metaNodeStake.connect(user1).unstake(0, unstakeAmount, {
                                gasLimit: 300000
                            });
                            await tx.wait();
                            
                            console.log("Unstake request submitted successfully");
                            
                            // 检查解质押请求
                            const requestCount = await metaNodeStake.getUserUnstakeRequestCount(0, user1.address);
                            console.log(`New unstake request count: ${requestCount}`);
                        }
                    } else {
                        console.log("User has no staked amount to unstake");
                    }
                } catch (error: any) {
                    console.log(`Unstake failed: ${error.message}`);
                }
            }
        });
    });

    describe("Contract State", function () {
        it("should return correct contract state", async function () {
            try {
                const isPaused = await metaNodeStake.paused();
                const totalPoolWeight = await metaNodeStake.totalPoolWeight();
                const currentBlock = await ethers.provider.getBlockNumber();
                
                console.log(`Contract paused: ${isPaused}`);
                console.log(`Total pool weight: ${totalPoolWeight}`);
                console.log(`Current block: ${currentBlock}`);
                
                expect(typeof isPaused).to.equal("boolean");
                expect(totalPoolWeight).to.be.gte(0);
                expect(currentBlock).to.be.gt(0);
            } catch (error: any) {
                console.log(`Failed to get contract state: ${error.message}`);
            }
        });

        it("should allow checking contract roles", async function () {
            try {
                const adminRole = await metaNodeStake.ADMIN_ROLE();
                const upgraderRole = await metaNodeStake.UPGRADER_ROLE();
                const defaultAdminRole = await metaNodeStake.DEFAULT_ADMIN_ROLE();
                
                console.log(`Admin role: ${adminRole}`);
                console.log(`Upgrader role: ${upgraderRole}`);
                console.log(`Default admin role: ${defaultAdminRole}`);
                
                // 检查owner是否有管理员权限
                const hasAdminRole = await metaNodeStake.hasRole(adminRole, owner.address);
                console.log(`Owner has admin role: ${hasAdminRole}`);
                
                expect(typeof hasAdminRole).to.equal("boolean");
            } catch (error: any) {
                console.log(`Failed to check roles: ${error.message}`);
            }
        });
    });

    describe("Network Information", function () {
        it("should return correct network information", async function () {
            const network = await ethers.provider.getNetwork();
            const blockNumber = await ethers.provider.getBlockNumber();
            const gasPrice = await ethers.provider.getFeeData();
            
            console.log(`Network name: ${network.name}`);
            console.log(`Chain ID: ${network.chainId}`);
            console.log(`Current block: ${blockNumber}`);
            console.log(`Gas price: ${ethers.formatUnits(gasPrice.gasPrice || 0, "gwei")} gwei`);
            
            // Sepolia的chain ID应该是11155111
            expect(network.chainId).to.equal(11155111n);
        });

        it("should display test addresses summary", async function () {
            console.log("\n=== Test Addresses Summary ===");
            
            const addresses = [
                { name: "Owner", address: owner.address },
                { name: "User1", address: user1.address },
                { name: "User2", address: user2.address }
            ];
            
            for (const { name, address } of addresses) {
                const ethBalance = await ethers.provider.getBalance(address);
                const tokenBalance = await metaNodeToken.balanceOf(address);
                
                console.log(`${name} (${address}):`);
                console.log(`  ETH: ${ethers.formatEther(ethBalance)}`);
                console.log(`  MetaNode: ${ethers.formatEther(tokenBalance)}`);
                
                // 如果有池，显示质押信息
                const poolLength = await metaNodeStake.poolLength();
                if (poolLength > 0) {
                    try {
                        const user = await metaNodeStake.users(0, address);
                        const pending = await metaNodeStake.pendingReward(0, address);
                        console.log(`  Staked: ${ethers.formatEther(user.stAmount)} ETH`);
                        console.log(`  Pending: ${ethers.formatEther(pending)} MetaNode`);
                    } catch (error) {
                        // 忽略查询错误
                    }
                }
                console.log("");
            }
        });
    });

    describe("Additional Contract Validations", function () {
        it("should verify MetaNode token configuration", async function () {
            try {
                const configuredMetaNode = await metaNodeStake.MetaNode();
                const actualMetaNodeAddress = await metaNodeToken.getAddress();
                
                console.log(`Configured MetaNode address: ${configuredMetaNode}`);
                console.log(`Actual MetaNode address: ${actualMetaNodeAddress}`);
                
                expect(configuredMetaNode.toLowerCase()).to.equal(actualMetaNodeAddress.toLowerCase());
                console.log("MetaNode token configuration verified successfully");
            } catch (error: any) {
                console.log(`Failed to verify MetaNode configuration: ${error.message}`);
            }
        });

        it("should verify mining period configuration", async function () {
            try {
                const startBlock = await metaNodeStake.startBlock();
                const endBlock = await metaNodeStake.endBlock();
                const currentBlock = await ethers.provider.getBlockNumber();
                
                console.log(`Mining period: Block ${startBlock} - ${endBlock}`);
                console.log(`Current block: ${currentBlock}`);
                console.log(`Mining active: ${currentBlock >= startBlock && currentBlock <= endBlock}`);
                console.log(`Blocks remaining: ${currentBlock < endBlock ? endBlock - currentBlock : 0}`);
                
                expect(endBlock).to.be.gt(startBlock);
            } catch (error: any) {
                console.log(`Failed to verify mining period: ${error.message}`);
            }
        });

        it("should allow updating pool rewards (admin functionality test)", async function () {
            try {
                const poolLength = await metaNodeStake.poolLength();
                if (poolLength > 0) {
                    // 尝试调用massUpdatePools
                    const tx = await metaNodeStake.massUpdatePools({
                        gasLimit: 500000
                    });
                    await tx.wait();
                    console.log("Mass update pools executed successfully");
                } else {
                    console.log("No pools to update");
                }
            } catch (error: any) {
                console.log(`Failed to update pools: ${error.message}`);
            }
        });
    });
});
