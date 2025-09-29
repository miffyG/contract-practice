# MyMeme 代币合约操作指南

MyMeme 是一个基于 ERC20 的模因代币项目，集成了自动做市商(AMM)流动性池功能，支持代币交易、流动性管理和税收机制。

## 项目架构

本项目包含两个核心合约：

### 1. MyMeme.sol - 主代币合约
- **代币标准**: ERC20 + ERC20Burnable
- **总供应量**: 2,000,000 MMM 代币
- **代币符号**: MMM
- **小数位**: 18
- **特殊功能**:
  - 买入税费: 5% (可调整)
  - 卖出税费: 8% (可调整)
  - 税费分配: 营销40% | 开发30% | 流动性30%
  - 交易限制: 每日交易次数限制
  - 黑名单机制
  - 暂停功能

### 2. LiquidityPool.sol - 流动性池合约
- **功能**: 自动做市商(AMM)
- **交易费**: 0.3%
- **支持操作**:
  - 添加/移除流动性
  - 代币买入/卖出
  - 价格自动发现

## 部署信息

### Sepolia测试网部署地址
- **MyMeme 合约**: `0x3FF78648bB540F2289795207FcB4c3E70D7A4F43`
- **LiquidityPool 合约**: `0x47fc79398620B5B67e279994A835353a7f3143A8`

### 部署参数配置
```json
{
  "MyMemeModule": {
    "tokenName": "MyMeme",
    "tokenSymbol": "MMM", 
    "totalSupply": "2000000000000000000000000",
    "marketingWallet": "0x9fb29f63ab634089be0c343a23fe7c2aeaf7682e",
    "devWallet": "0x9fb29f63ab634089be0c343a23fe7c2aeaf7682e",
    "liquidityWallet": "0x9fb29f63ab634089be0c343a23fe7c2aeaf7682e"
  }
}
```

## 环境配置

### 1. 安装依赖
```bash
npm install
```

### 2. 环境变量配置
创建 `.env` 文件并配置以下变量：
```env
# Sepolia 测试网配置
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_PROJECT_ID
SEPOLIA_PRIVATE_KEY=0x...

# 其他网络配置（如需要）
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_PROJECT_ID
MAINNET_PRIVATE_KEY=0x...
```

### 3. 编译合约
```bash
npx hardhat compile
```

## 部署操作

### 本地测试网部署
```bash
# 启动本地 Hardhat 网络
npx hardhat node

# 在另一个终端部署合约
npm run deploy
```

### Sepolia 测试网部署
```bash
npm run deploy -- --network sepolia
```

### 生产环境部署
```bash
# 使用生产配置编译
npx hardhat compile --config hardhat.production.config.ts

# 部署到主网
npm run deploy -- --network mainnet
```

## 合约交互指南

### 1. 代币基础操作

#### 查看代币信息
```javascript
// 使用 ethers.js
const myMeme = await ethers.getContractAt("MyMeme", "0x5FbDB2315678afecb367f032d93F642f64180aa3");

// 获取基本信息
const name = await myMeme.name();
const symbol = await myMeme.symbol();
const totalSupply = await myMeme.totalSupply();
const decimals = await myMeme.decimals();

console.log(`代币名称: ${name}`);
console.log(`代币符号: ${symbol}`);
console.log(`总供应量: ${ethers.formatEther(totalSupply)} MMM`);
console.log(`小数位数: ${decimals}`);
```

#### 转账操作
```javascript
// 普通转账
const tx = await myMeme.transfer(recipientAddress, ethers.parseEther("100"));
await tx.wait();

// 授权转账
const approveTx = await myMeme.approve(spenderAddress, ethers.parseEther("100"));
await approveTx.wait();

const transferFromTx = await myMeme.transferFrom(ownerAddress, recipientAddress, ethers.parseEther("100"));
await transferFromTx.wait();
```

### 2. 流动性池操作

#### 初始化流动性池
```javascript
const liquidityPool = await ethers.getContractAt("LiquidityPool", "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512");

// 首次添加流动性（需要先授权代币）
const tokenAmount = ethers.parseEther("10000"); // 10,000 MMM
const ethAmount = ethers.parseEther("1"); // 1 ETH

// 1. 授权代币给流动性池
await myMeme.approve(liquidityPool.target, tokenAmount);

// 2. 添加流动性
const addLiquidityTx = await liquidityPool.addLiquidity(tokenAmount, {
  value: ethAmount
});
await addLiquidityTx.wait();
```

#### 添加流动性
```javascript
// 后续添加流动性（自动按比例计算）
const tokenAmount = ethers.parseEther("1000"); // 要添加的代币数量
const ethAmount = ethers.parseEther("0.1"); // 要添加的ETH数量

// 授权代币
await myMeme.approve(liquidityPool.target, tokenAmount);

// 添加流动性
const tx = await liquidityPool.addLiquidity(tokenAmount, { value: ethAmount });
await tx.wait();

console.log("流动性添加成功！");
```

#### 移除流动性
```javascript
// 查看用户的流动性份额
const userShares = await liquidityPool.liquidityShares(userAddress);
console.log(`用户流动性份额: ${userShares}`);

// 移除部分流动性（例如移除50%）
const sharesToRemove = userShares / 2n;
const removeTx = await liquidityPool.removeLiquidity(sharesToRemove);
await removeTx.wait();

console.log("流动性移除成功！");
```

### 3. 代币交易操作

#### 购买代币（ETH -> MMM）
```javascript
// 计算可购买的代币数量
const ethAmount = ethers.parseEther("0.1"); // 用0.1 ETH购买
const expectedTokens = await liquidityPool.getTokenAmountOut(ethAmount);
console.log(`预计获得: ${ethers.formatEther(expectedTokens)} MMM`);

// 执行购买
const buyTx = await liquidityPool.buyTokens(0, { // 0表示不设置最小接收量
  value: ethAmount
});
await buyTx.wait();

console.log("代币购买成功！");
```

#### 出售代币（MMM -> ETH）
```javascript
const tokenAmount = ethers.parseEther("100"); // 卖出100 MMM

// 计算可获得的ETH数量
const expectedEth = await liquidityPool.getEthAmountOut(tokenAmount);
console.log(`预计获得: ${ethers.formatEther(expectedEth)} ETH`);

// 授权代币给流动性池
await myMeme.approve(liquidityPool.target, tokenAmount);

// 执行卖出
const sellTx = await liquidityPool.sellTokens(tokenAmount, 0); // 0表示不设置最小接收量
await sellTx.wait();

console.log("代币卖出成功！");
```

### 4. 价格查询

#### 获取当前价格
```javascript
// 获取储备量
const tokenReserve = await liquidityPool.tokenReserve();
const ethReserve = await liquidityPool.ethReserve();

// 计算价格 (ETH per MMM)
const priceInETH = ethReserve * ethers.parseEther("1") / tokenReserve;
console.log(`当前价格: 1 MMM = ${ethers.formatEther(priceInETH)} ETH`);

// 计算购买1个ETH能得到多少代币
const oneEth = ethers.parseEther("1");
const tokensFor1ETH = await liquidityPool.getTokenAmountOut(oneEth);
console.log(`1 ETH 可购买: ${ethers.formatEther(tokensFor1ETH)} MMM`);
```

### 5. 管理功能（仅合约所有者）

#### 税费管理
```javascript
// 更新税费率
const newBuyTax = 300; // 3%
const newSellTax = 500; // 5%
const updateTaxTx = await myMeme.updateTaxRates(newBuyTax, newSellTax);
await updateTaxTx.wait();

// 分配累计的税费
const distributeTx = await myMeme.distributeTax();
await distributeTx.wait();
```

#### 黑名单管理
```javascript
// 添加到黑名单
const blacklistTx = await myMeme.addToBlacklist(suspiciousAddress);
await blacklistTx.wait();

// 从黑名单移除
const removeBlacklistTx = await myMeme.removeFromBlacklist(rehabilitatedAddress);
await removeBlacklistTx.wait();
```

#### 交易限制管理
```javascript
// 设置交易限制
const maxTxAmount = ethers.parseEther("1000"); // 最大单笔交易1000 MMM
const setLimitTx = await myMeme.setMaxTransactionAmount(maxTxAmount);
await setLimitTx.wait();

// 添加到免费白名单
const excludeTx = await myMeme.excludeFromFees(whitelistAddress, true);
await excludeTx.wait();
```

#### 紧急控制
```javascript
// 暂停合约
const pauseTx = await myMeme.pause();
await pauseTx.wait();

// 恢复合约
const unpauseTx = await myMeme.unpause();
await unpauseTx.wait();
```

## 测试

### 运行所有测试
```bash
npm test
```

### 运行特定测试文件
```bash
npx hardhat test test/MyMeme.test.js
npx hardhat test test/LiquidityPool.test.js
```

### 测试覆盖率
```bash
npx hardhat coverage
```

## 监控和事件

### 重要事件监听
```javascript
// 监听代币转账
myMeme.on("Transfer", (from, to, value) => {
  console.log(`转账: ${from} -> ${to}, 数量: ${ethers.formatEther(value)} MMM`);
});

// 监听税费分配
myMeme.on("TaxDistributed", (marketing, development, liquidity) => {
  console.log("税费分配完成:", {
    营销: ethers.formatEther(marketing),
    开发: ethers.formatEther(development), 
    流动性: ethers.formatEther(liquidity)
  });
});

// 监听流动性变化
liquidityPool.on("LiquidityAdded", (user, tokenAmount, ethAmount, shares) => {
  console.log(`流动性添加: 用户${user}, 代币${ethers.formatEther(tokenAmount)}, ETH${ethers.formatEther(ethAmount)}`);
});

// 监听交易
liquidityPool.on("TokenPurchased", (buyer, ethAmount, tokenAmount) => {
  console.log(`代币购买: ${buyer} 用 ${ethers.formatEther(ethAmount)} ETH 购买了 ${ethers.formatEther(tokenAmount)} MMM`);
});
```

## 安全注意事项

### 1. 滑点保护
在执行交易时，建议设置合理的最小接收量以防止MEV攻击：
```javascript
// 设置5%滑点保护
const expectedTokens = await liquidityPool.getTokenAmountOut(ethAmount);
const minTokens = expectedTokens * 95n / 100n; // 95% of expected

const tx = await liquidityPool.buyTokens(minTokens, { value: ethAmount });
```

### 2. 税费考量
买卖代币时会产生税费，实际到账金额会少于预期：
- 买入税费：5%（可调整）
- 卖出税费：8%（可调整）

### 3. 交易限制
注意每日交易次数限制（默认10次），频繁交易可能被限制。

### 4. 黑名单检查
被加入黑名单的地址无法进行代币转账。

## 故障排除

### 常见问题

#### 1. 交易失败 - "Insufficient balance"
**原因**: 账户余额不足
**解决**: 检查ETH和MMM余额是否足够支付gas费和交易金额

#### 2. 交易失败 - "ERC20: insufficient allowance" 
**原因**: 未授权或授权额度不足
**解决**: 先调用approve()方法授权足够的代币额度

#### 3. 交易失败 - "Slippage tolerance exceeded"
**原因**: 价格滑点过大
**解决**: 增加滑点容忍度或减少交易金额

#### 4. 交易失败 - "Daily transaction limit exceeded"
**原因**: 达到每日交易次数限制
**解决**: 等待次日重置或联系管理员加入白名单

### Gas 优化建议

1. **批量操作**: 尽量将多个操作打包在一个交易中
2. **合理gas价格**: 根据网络拥堵情况设置合适的gas价格
3. **避免频繁小额交易**: 减少不必要的链上交互

## 升级和维护

### 合约升级
当前合约不支持升级，如需更新功能需要重新部署。建议：
1. 提前通知用户
2. 提供迁移工具
3. 保留原合约一段时间供用户提取资金

### 定期维护
1. 监控合约状态和资金安全
2. 定期分配累计税费
3. 及时更新黑名单
4. 监控异常交易模式

---

⚠️ **免责声明**: 本合约仅用于学习和测试目的。投资有风险，请在充分了解风险的情况下参与。