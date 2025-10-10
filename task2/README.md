# MetaNodeStake - 可升级质押合约

基于 Hardhat 3.0 开发的去中心化质押系统，支持ETH质押和MetaNode代币奖励。

## 功能特性

- 🔒 **ETH质押**：质押ETH获取MetaNode代币奖励
- ⬆️ **可升级**：采用UUPS代理模式，支持合约升级  
- ⏰ **分时挖矿**：基于区块高度的奖励分配
- 🔐 **安全提取**：解质押锁定机制保障资金安全

## 快速开始

```bash
# 安装依赖
npm install

# 部署到Sepolia
npm run deployToSepolia

# 运行测试
npm test
```

## 已部署合约 (Sepolia)

- MetaNodeToken: `0xB0EfEad00Aca442dd835845B9F6f5d9eCf76efc4`
- MetaNodeStake: `0x2940Ffd4613391ADBd13DCFacbDA4a5ffa6344A4`

## 在sepolia上测试通过
```
npx hardhat test test/test_on_sepolia.ts --network sepolia
```

## 技术栈

Solidity 0.8.28 | Hardhat 3.0 | OpenZeppelin | TypeScript