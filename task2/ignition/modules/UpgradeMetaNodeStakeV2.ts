import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import MetaNodeStakeModule from "./MetaNodeStake.js";

const UpgradeMetaNodeStakeV2Module = buildModule("UpgradeMetaNodeStakeV2Module", (m) => {
    // 获取MetaNodeStakeV2合约
    const metaNodeStakeV2Impl = m.contract("MetaNodeStakeV2");

    // 获取MetaNodeStake代理合约地址
    const { metaNodeStake } = m.useModule(MetaNodeStakeModule);

    m.call(metaNodeStake, "upgradeToAndCall", [metaNodeStakeV2Impl, "0x"]);

    return { metaNodeStakeV2Impl};
});

export default UpgradeMetaNodeStakeV2Module;