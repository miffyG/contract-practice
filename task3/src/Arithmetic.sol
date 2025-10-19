// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract Arithmetic {

    uint256 public latestAddResult;
    uint256 public latestSubtractResult;
    uint256 public latestMultiplyResult;
    uint256 public latestDivideResult;

    function add(uint256 a, uint256 b) external returns (uint256) {
        latestAddResult = a + b;
        return latestAddResult;
    }

    function subtract(uint256 a, uint256 b) external returns (uint256) {
        latestSubtractResult = a - b;
        return latestSubtractResult;
    }

    function multiply(uint256 a, uint256 b) external returns (uint256) {
        latestMultiplyResult = a * b;
        return latestMultiplyResult;
    }

    function divide(uint256 a, uint256 b) external returns (uint256) {
        require(b != 0, "Division by zero");
        latestDivideResult = a / b;
        return latestDivideResult;
    }
}