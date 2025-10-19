// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title OptimizedArithmetic1
 * @notice Gas Optimization Strategy 1: Remove state storage, use pure functions
 * @dev By removing state variables and SSTORE operations, we eliminate the most
 *      expensive gas costs. Functions become pure, only computing and returning results.
 */
contract OptimizedArithmetic1 {
    // No state variables - eliminates expensive SSTORE operations
    // Original contract used ~20,000 gas per SSTORE

    function add(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }

    function subtract(uint256 a, uint256 b) external pure returns (uint256) {
        return a - b;
    }

    function multiply(uint256 a, uint256 b) external pure returns (uint256) {
        return a * b;
    }

    function divide(uint256 a, uint256 b) external pure returns (uint256) {
        require(b != 0, "Division by zero");
        return a / b;
    }
}