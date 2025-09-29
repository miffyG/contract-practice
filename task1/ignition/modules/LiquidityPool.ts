import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import MyMemeModule from "./MyMeme.js";

export default buildModule("LiquidityPoolModule", (m) => {
  // 依赖 MyMemeModule 来获取代币合约地址
  const { myMeme } = m.useModule(MyMemeModule);

  // 部署 LiquidityPool 合约，使用 MyMeme 合约地址作为参数
  const liquidityPool = m.contract("LiquidityPool", [myMeme]);

  // 设置 MyMeme 合约的流动性池地址
  // 这样 MyMeme 合约就知道它的流动性池在哪里
  const setLiquidityPoolCall = m.call(myMeme, "setLiquidityPool", [liquidityPool], {
    id: "setLiquidityPool"
  });

  return { liquidityPool, myMeme };
});
