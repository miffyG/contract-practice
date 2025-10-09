// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MetaNodeStake.sol";

contract MetaNodeStakeV2 is MetaNodeStake {
    // 新增一个函数，返回一个固定值，表示这是V2版本
    function version() external pure returns (string memory) {
        return "V2";
    }
}