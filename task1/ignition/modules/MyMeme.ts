import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MyMemeModule", (m) => {
  // 代币基本参数
  const tokenName = m.getParameter("tokenName", "MyMeme");
  const tokenSymbol = m.getParameter("tokenSymbol", "MEME");
  const totalSupply = m.getParameter("totalSupply", 1000000n * 10n ** 18n); // 1,000,000 tokens with 18 decimals

  // 钱包地址参数
  const marketingWallet = m.getParameter("marketingWallet", "0x742d35Cc8C6C165C4bA2d4b7a2c9F6D8D3dB3F39");
  const devWallet = m.getParameter("devWallet", "0x8ba1f109551bD432803012645Hac136c4c2dB3F9");
  const liquidityWallet = m.getParameter("liquidityWallet", "0x9ca2f109551bD432803012645Hac136c4c2db4F0");

  // 部署 MyMeme 合约
  const myMeme = m.contract("MyMeme", [
    tokenName,
    tokenSymbol,
    totalSupply,
    marketingWallet,
    devWallet,
    liquidityWallet
  ]);

  return { myMeme };
});

