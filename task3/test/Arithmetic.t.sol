// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Arithmetic} from "../src/Arithmetic.sol";

contract ArithmeticTest is Test {
    Arithmetic public arithmetic;

    function setUp() public {
        arithmetic = new Arithmetic();
    }

    function test_Add() public {
        uint256 result = arithmetic.add(2, 3);
        assertEq(result, 5);
    }

    function testFuzz_Add(uint256 a, uint256 b) public {
        vm.assume(a <= type(uint256).max - b); // Prevent overflow
        uint256 result = arithmetic.add(a, b);
        assertEq(result, a + b);
    }

    function test_Subtract() public {
        uint256 result = arithmetic.subtract(5, 3);
        assertEq(result, 2);
    }

    function testFuzz_Subtract(uint256 a, uint256 b) public {
        vm.assume(a >= b); // Ensure no underflow
        uint256 result = arithmetic.subtract(a, b);
        assertEq(result, a - b);
    }

    function test_Multiply() public {
        uint256 result = arithmetic.multiply(2, 3);
        assertEq(result, 6);
    }

    function testFuzz_Multiply(uint256 a, uint256 b) public {
        vm.assume(a == 0 || b <= type(uint256).max / a); // Prevent overflow
        uint256 result = arithmetic.multiply(a, b);
        assertEq(result, a * b);
    }

    function test_Divide() public {
        uint256 result = arithmetic.divide(6, 3);
        assertEq(result, 2);
    }

    function testFuzz_Divide(uint256 a, uint256 b) public {
        vm.assume(b != 0); // Prevent division by zero
        uint256 result = arithmetic.divide(a, b);
        assertEq(result, a / b);
    }

    function test_DivideByZero() public {
        vm.expectRevert("Division by zero");
        arithmetic.divide(6, 0);
    }
}