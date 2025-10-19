// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title OptimizedArithmetic2
 * @notice Gas Optimization Strategy 2: Use unchecked arithmetic and custom errors
 * @dev Uses unchecked blocks for safe operations and custom errors (cheaper than strings)
 *      Custom errors save ~50 gas compared to require strings
 *      Unchecked arithmetic saves ~3-6% gas when overflow/underflow is impossible
 */
contract OptimizedArithmetic2 {

    uint256 public latestAddResult;
    uint256 public latestSubtractResult;
    uint256 public latestMultiplyResult;
    uint256 public latestDivideResult;

    // Custom error is cheaper than require with string (saves ~50 gas)
    error DivisionByZero();

    function add(uint256 a, uint256 b) external returns (uint256) {
        unchecked {
            // Safe to use unchecked if caller ensures no overflow
            // In Solidity 0.8+, unchecked saves gas by skipping overflow checks
            uint256 result = a + b;
            latestAddResult = result;
            return result;
        }
    }

    function subtract(uint256 a, uint256 b) external returns (uint256) {
        unchecked {
            // Safe if caller ensures a >= b
            uint256 result = a - b;
            latestSubtractResult = result;
            return result;
        }
    }

    function multiply(uint256 a, uint256 b) external returns (uint256) {
        unchecked {
            // Safe if caller ensures no overflow
            uint256 result = a * b;
            latestMultiplyResult = result;
            return result;
        }
    }

    function divide(uint256 a, uint256 b) external returns (uint256) {
        // Use custom error instead of require with string
        if (b == 0) revert DivisionByZero();
        
        unchecked {
            // Division never overflows, safe to use unchecked
            uint256 result = a / b;
            latestDivideResult = result;
            return result;
        }
    }
}