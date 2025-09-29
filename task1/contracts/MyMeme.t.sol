// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MyMeme} from "./MyMeme.sol";

contract MyMemeTest is Test {
    MyMeme public myMeme;

    address public owner = address(0x1);
    address public marketingWallet = address(0x2);
    address public developmentWallet = address(0x3);
    address public liquidityWallet = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);
    address public blacklistedUser = address(0x7);
    address public liquidityPool = address(0x8);

    uint256 public constant TOTAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant INITIAL_ETH = 100 ether;
    uint256 public constant INITIAL_TOKENS = 10_000 * 10**18;

    function setUp() public {
        vm.startPrank(owner);
        myMeme = new MyMeme(
            "MyMeme",
            "MEME",
            TOTAL_SUPPLY,
            marketingWallet,
            developmentWallet,
            liquidityWallet
        );
        vm.stopPrank();

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(owner, 1000 ether);
    }

    // Constructor Tests
    function testConstructor() public {
        assertEq(myMeme.name(), "MyMeme");
        assertEq(myMeme.symbol(), "MEME");
        assertEq(myMeme.totalSupply(), TOTAL_SUPPLY);
        assertEq(myMeme.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(myMeme.owner(), owner);
        assertEq(myMeme.marketingWallet(), marketingWallet);
        assertEq(myMeme.developmentWallet(), developmentWallet);
        assertEq(myMeme.liquidityWallet(), liquidityWallet);
        assertEq(myMeme.maxTransactionAmount(), TOTAL_SUPPLY / 100);
        assertTrue(myMeme.isExcludedFromFees(owner));
        assertTrue(myMeme.isExcludedFromFees(address(myMeme)));
        assertTrue(myMeme.isExcludedFromLimits(owner));
        assertTrue(myMeme.isExcludedFromLimits(address(myMeme)));
    }

    function testConstructorZeroAddresses() public {
        vm.expectRevert("Marketing wallet cannot be zero address");
        new MyMeme("Test", "TEST", TOTAL_SUPPLY, address(0), developmentWallet, liquidityWallet);

        vm.expectRevert("Dev wallet cannot be zero address");
        new MyMeme("Test", "TEST", TOTAL_SUPPLY, marketingWallet, address(0), liquidityWallet);

        vm.expectRevert("Liquidity wallet cannot be zero address");
        new MyMeme("Test", "TEST", TOTAL_SUPPLY, marketingWallet, developmentWallet, address(0));
    }

    // Tax Rate Tests
    function testSetTaxRates() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.TaxRateUpdated(300, 500);
        myMeme.setTaxRates(300, 500);
        
        assertEq(myMeme.buyTaxRate(), 300);
        assertEq(myMeme.sellTaxRate(), 500);
        vm.stopPrank();
    }

    function testSetTaxRatesTooHigh() public {
        vm.startPrank(owner);
        
        vm.expectRevert("Buy tax rate too high");
        myMeme.setTaxRates(1600, 500);
        
        vm.expectRevert("Sell tax rate too high");
        myMeme.setTaxRates(500, 1600);
        
        vm.stopPrank();
    }

    function testSetTaxRatesOnlyOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        myMeme.setTaxRates(300, 500);
        vm.stopPrank();
    }

    // Transaction Limits Tests
    function testSetTransactionLimits() public {
        vm.startPrank(owner);
        
        uint256 newMaxTx = TOTAL_SUPPLY / 200;
        uint256 newDailyLimit = 20;
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.TransactionLimitsUpdated(newMaxTx, newDailyLimit);
        myMeme.setTransactionLimits(newMaxTx, newDailyLimit);
        
        assertEq(myMeme.maxTransactionAmount(), newMaxTx);
        assertEq(myMeme.dailyTransactionLimit(), newDailyLimit);
        vm.stopPrank();
    }

    function testSetTransactionLimitsZeroValues() public {
        vm.startPrank(owner);
        
        vm.expectRevert("Max transaction amount must be greater than zero");
        myMeme.setTransactionLimits(0, 10);
        
        vm.expectRevert("Daily transaction limit must be greater than zero");
        myMeme.setTransactionLimits(1000, 0);
        
        vm.stopPrank();
    }

    // Exclusion Tests
    function testSetExcludedFromFees() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromFeesUpdated(user1, true);
        myMeme.setExcludedFromFees(user1, true);
        
        assertTrue(myMeme.isExcludedFromFees(user1));
        assertTrue(myMeme.checkExcludedFromFees(user1));
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromFeesUpdated(user1, false);
        myMeme.setExcludedFromFees(user1, false);
        
        assertFalse(myMeme.isExcludedFromFees(user1));
        vm.stopPrank();
    }

    function testSetExcludedFromFeesZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("Invalid address");
        myMeme.setExcludedFromFees(address(0), true);
        vm.stopPrank();
    }

    function testSetExcludedFromFeesBatch() public {
        vm.startPrank(owner);
        
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromFeesUpdated(user1, true);
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromFeesUpdated(user2, true);
        myMeme.setExcludedFromFeesBatch(accounts, true);
        
        assertTrue(myMeme.isExcludedFromFees(user1));
        assertTrue(myMeme.isExcludedFromFees(user2));
        vm.stopPrank();
    }

    function testSetExcludedFromLimits() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromLimitsUpdated(user1, true);
        myMeme.setExcludedFromLimits(user1, true);
        
        assertTrue(myMeme.isExcludedFromLimits(user1));
        assertTrue(myMeme.checkExcludedFromLimits(user1));
        vm.stopPrank();
    }

    function testSetExcludedFromLimitsBatch() public {
        vm.startPrank(owner);
        
        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user2;
        
        myMeme.setExcludedFromLimitsBatch(accounts, true);
        
        assertTrue(myMeme.isExcludedFromLimits(user1));
        assertTrue(myMeme.isExcludedFromLimits(user2));
        vm.stopPrank();
    }

    function testSetExcluded() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromFeesUpdated(user1, true);
        vm.expectEmit(true, true, true, true);
        emit MyMeme.ExcludedFromLimitsUpdated(user1, true);
        myMeme.setExcluded(user1, true, true);
        
        assertTrue(myMeme.isExcludedFromFees(user1));
        assertTrue(myMeme.isExcludedFromLimits(user1));
        vm.stopPrank();
    }

    // Blacklist Tests
    function testSetBlacklisted() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.UserBlacklisted(blacklistedUser, true);
        myMeme.setBlacklisted(blacklistedUser, true);
        
        assertTrue(myMeme.isBlacklisted(blacklistedUser));
        assertTrue(myMeme.checkIsBlacklisted(blacklistedUser));
        vm.stopPrank();
    }

    function testBlacklistedTransfer() public {
        vm.startPrank(owner);
        myMeme.setBlacklisted(user1, true);
        myMeme.transfer(user1, 1000);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert("Address is blacklisted");
        myMeme.transfer(user2, 500);
        vm.stopPrank();
    }

    // Transaction Limit Tests
    function testMaxTransactionLimit() public {
        vm.startPrank(owner);
        uint256 transferAmount = myMeme.maxTransactionAmount() + 1;
        myMeme.transfer(user1, transferAmount * 2);
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert("Exceeds max transaction amount");
        myMeme.transfer(user2, transferAmount);
        vm.stopPrank();
    }

    function testDailyTransactionLimit() public {
        vm.startPrank(owner);
        myMeme.transfer(user1, 1000 * 10**18);
        myMeme.setTransactionLimits(100 * 10**18, 2);
        vm.stopPrank();
        
        vm.startPrank(user1);
        // First transaction - should pass
        myMeme.transfer(user2, 50 * 10**18);
        
        // Second transaction - should pass
        myMeme.transfer(user2, 50 * 10**18);
        
        // Third transaction - should fail
        vm.expectRevert("Exceeds daily transaction limit");
        myMeme.transfer(user2, 50 * 10**18);
        vm.stopPrank();
    }

    function testGetRemainingDailyTransactions() public {
        vm.startPrank(owner);
        myMeme.transfer(user1, 1000 * 10**18);
        myMeme.setTransactionLimits(100 * 10**18, 5);
        vm.stopPrank();
        
        assertEq(myMeme.getRemainingDailyTransactions(user1), 5);
        
        vm.startPrank(user1);
        myMeme.transfer(user2, 50 * 10**18);
        vm.stopPrank();
        
        assertEq(myMeme.getRemainingDailyTransactions(user1), 4);
    }

    // Pause Tests
    function testPause() public {
        vm.startPrank(owner);
        myMeme.pause();
        assertTrue(myMeme.paused());
        
        vm.expectRevert();
        myMeme.transfer(user1, 1000);
        
        myMeme.unpause();
        assertFalse(myMeme.paused());
        myMeme.transfer(user1, 1000);
        vm.stopPrank();
    }

    // Liquidity Pool Tests
    function testSetLiquidityPool() public {
        vm.startPrank(owner);
        
        vm.expectEmit(true, true, true, true);
        emit MyMeme.LiquidityPoolUpdated(address(0), liquidityPool);
        myMeme.setLiquidityPool(liquidityPool);
        
        assertEq(myMeme.liquidityPool(), liquidityPool);
        assertTrue(myMeme.isExcludedFromFees(liquidityPool));
        assertTrue(myMeme.isExcludedFromLimits(liquidityPool));
        vm.stopPrank();
    }

    function testSetLiquidityPoolZeroAddress() public {
        vm.startPrank(owner);
        vm.expectRevert("Liquidity pool cannot be zero address");
        myMeme.setLiquidityPool(address(0));
        vm.stopPrank();
    }

    // View Function Tests
    function testGetTokenPriceNoPool() public {
        assertEq(myMeme.getTokenPrice(), 0);
    }

    function testGetUserLiquidityNoPool() public {
        (uint256 shares, uint256 tokenAmount, uint256 ethAmount) = myMeme.getUserLiquidity(user1);
        assertEq(shares, 0);
        assertEq(tokenAmount, 0);
        assertEq(ethAmount, 0);
    }

    function testGetReservesNoPool() public {
        (uint256 tokenReserve, uint256 ethReserve, uint256 totalShares) = myMeme.getReserves();
        assertEq(tokenReserve, 0);
        assertEq(ethReserve, 0);
        assertEq(totalShares, 0);
    }

    // ERC20 Basic Functions
    function testTransfer() public {
        vm.startPrank(owner);
        uint256 transferAmount = 1000 * 10**18;
        
        uint256 ownerBalanceBefore = myMeme.balanceOf(owner);
        uint256 user1BalanceBefore = myMeme.balanceOf(user1);
        
        myMeme.transfer(user1, transferAmount);
        
        assertEq(myMeme.balanceOf(owner), ownerBalanceBefore - transferAmount);
        assertEq(myMeme.balanceOf(user1), user1BalanceBefore + transferAmount);
        vm.stopPrank();
    }

    function testApproveAndTransferFrom() public {
        vm.startPrank(owner);
        uint256 approveAmount = 1000 * 10**18;
        
        myMeme.approve(user1, approveAmount);
        assertEq(myMeme.allowance(owner, user1), approveAmount);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 transferAmount = 500 * 10**18;
        uint256 ownerBalanceBefore = myMeme.balanceOf(owner);
        uint256 user2BalanceBefore = myMeme.balanceOf(user2);
        
        myMeme.transferFrom(owner, user2, transferAmount);
        
        assertEq(myMeme.balanceOf(owner), ownerBalanceBefore - transferAmount);
        assertEq(myMeme.balanceOf(user2), user2BalanceBefore + transferAmount);
        assertEq(myMeme.allowance(owner, user1), approveAmount - transferAmount);
        vm.stopPrank();
    }

    function testBurn() public {
        vm.startPrank(owner);
        uint256 burnAmount = 1000 * 10**18;
        uint256 balanceBefore = myMeme.balanceOf(owner);
        uint256 totalSupplyBefore = myMeme.totalSupply();
        
        myMeme.burn(burnAmount);
        
        assertEq(myMeme.balanceOf(owner), balanceBefore - burnAmount);
        assertEq(myMeme.totalSupply(), totalSupplyBefore - burnAmount);
        vm.stopPrank();
    }

    function testBurnFrom() public {
        vm.startPrank(owner);
        uint256 approveAmount = 1000 * 10**18;
        myMeme.approve(user1, approveAmount);
        vm.stopPrank();
        
        vm.startPrank(user1);
        uint256 burnAmount = 500 * 10**18;
        uint256 ownerBalanceBefore = myMeme.balanceOf(owner);
        uint256 totalSupplyBefore = myMeme.totalSupply();
        
        myMeme.burnFrom(owner, burnAmount);
        
        assertEq(myMeme.balanceOf(owner), ownerBalanceBefore - burnAmount);
        assertEq(myMeme.totalSupply(), totalSupplyBefore - burnAmount);
        vm.stopPrank();
    }

    // Receive ETH Test
    function testReceiveETH() public {
        uint256 ethAmount = 1 ether;
        vm.deal(user1, ethAmount);
        
        uint256 contractBalanceBefore = address(myMeme).balance;
        
        vm.startPrank(user1);
        (bool success,) = address(myMeme).call{value: ethAmount}("");
        assertTrue(success);
        vm.stopPrank();
        
        assertEq(address(myMeme).balance, contractBalanceBefore + ethAmount);
    }

    // Tax Constants Tests
    function testTaxConstants() public {
        assertEq(myMeme.MAX_TAX_RATE(), 1500);
        assertEq(myMeme.TAX_DIVISOR(), 10000);
        assertEq(myMeme.buyTaxRate(), 500);
        assertEq(myMeme.sellTaxRate(), 800);
        assertEq(myMeme.marketingShare(), 40);
        assertEq(myMeme.developmentShare(), 30);
        assertEq(myMeme.liquidityShare(), 30);
    }

    // Access Control Tests
    function testOnlyOwnerFunctions() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        myMeme.setTaxRates(300, 400);
        
        vm.expectRevert();
        myMeme.setTransactionLimits(1000, 5);
        
        vm.expectRevert();
        myMeme.setExcludedFromFees(user2, true);
        
        vm.expectRevert();
        myMeme.setBlacklisted(user2, true);
        
        vm.expectRevert();
        myMeme.pause();
        
        vm.expectRevert();
        myMeme.setLiquidityPool(liquidityPool);
        
        vm.stopPrank();
    }
}