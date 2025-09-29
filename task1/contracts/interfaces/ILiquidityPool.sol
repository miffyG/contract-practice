// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ILiquidityPool {
    function getTokenPrice() external view returns (uint256);
    function getReserves() external view returns (uint256, uint256, uint256);
    function getUserLiquidity(address account) external view returns (uint256, uint256, uint256);
}
