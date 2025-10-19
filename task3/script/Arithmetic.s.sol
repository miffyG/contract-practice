// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Arithmetic} from "../src/Arithmetic.sol";

contract ArithmeticScript is Script {

    Arithmetic public arithmetic;

    function run() public {
        vm.startBroadcast();
        arithmetic = new Arithmetic();
        vm.stopBroadcast();
    }
}