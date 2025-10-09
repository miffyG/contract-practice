import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MetaNodeStakeModule = buildModule("MetaNodeStakeModule", (m) => {
  // 部署MetaNode代币合约
  const metaNodeToken = m.contract("MetaNodeToken");

  // 部署参数
  const metaNodePerBlock = m.getParameter("metaNodePerBlock", "1000000000000000000");
  const startBlock = m.getParameter("startBlock", 1);
  const blocksPerDay = 86400 / 12; // 假设12秒一个区块
  const durationDays = m.getParameter("durationDays", 365); // 默认1年
  const endBlock = m.getParameter("endBlock", Math.floor(blocksPerDay * 365));

  // 部署MetaNodeStake实现合约
  const metaNodeStakeImpl = m.contract("MetaNodeStake");

  // 创建初始化数据
  const initializeData = m.encodeFunctionCall(metaNodeStakeImpl, "initialize", [
    metaNodeToken,
    metaNodePerBlock,
    startBlock,
    endBlock
  ]);

  // 部署ERC1967代理
  const proxy = m.contract("ERC1967Proxy", [
    metaNodeStakeImpl,
    initializeData
  ]);

  // 使用代理地址创建MetaNodeStake接口
  const metaNodeStake = m.contractAt("MetaNodeStake", proxy, {
    id: "MetaNodeStakeProxy"
  });

  return { metaNodeToken, proxy, metaNodeStake };
});

export default MetaNodeStakeModule;