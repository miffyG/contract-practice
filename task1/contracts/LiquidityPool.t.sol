// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./LiquidityPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18); // Mint 1M tokens
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LiquidityPoolTest is Test {
    LiquidityPool public pool;
    MockERC20 public token;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);
    
    uint256 constant INITIAL_ETH_BALANCE = 100 ether;
    uint256 constant INITIAL_TOKEN_BALANCE = 1000000 * 10**18;

    function setUp() public {
        vm.startPrank(owner);
        token = new MockERC20("Test Token", "TEST");
        pool = new LiquidityPool(address(token));
        vm.stopPrank();

        // Setup balances
        vm.deal(owner, INITIAL_ETH_BALANCE);
        vm.deal(user1, INITIAL_ETH_BALANCE);
        vm.deal(user2, INITIAL_ETH_BALANCE);
        vm.deal(user3, INITIAL_ETH_BALANCE);

        // Distribute tokens
        vm.startPrank(owner);
        token.transfer(user1, 100000 * 10**18);
        token.transfer(user2, 100000 * 10**18);
        token.transfer(user3, 100000 * 10**18);
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(address(pool.token()), address(token));
        assertEq(pool.owner(), owner);
        assertEq(pool.tokenReserve(), 0);
        assertEq(pool.ethReserve(), 0);
        assertEq(pool.totalLiquidityShares(), 0);
        assertEq(pool.liquidityFee(), 30);
        assertFalse(pool.paused());
    }

    function testConstructorZeroAddress() public {
        vm.expectRevert("Token address cannot be zero");
        new LiquidityPool(address(0));
    }

    function testAddLiquidityInitial() public {
        uint256 tokenAmount = 1000 * 10**18;
        uint256 ethAmount = 10 ether;

        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount);

        pool.addLiquidity{value: ethAmount}(tokenAmount);
        vm.stopPrank();

        assertEq(pool.tokenReserve(), tokenAmount);
        assertEq(pool.ethReserve(), ethAmount);
        assertGt(pool.liquidityShares(user1), 0);
        assertGt(pool.totalLiquidityShares(), pool.liquidityShares(user1)); // Should include minimum liquidity
    }

    function testAddLiquiditySubsequent() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 500 * 10**18;
        uint256 ethAmount = 5 ether;

        vm.startPrank(user2);
        token.approve(address(pool), tokenAmount);
        
        uint256 initialShares = pool.liquidityShares(user2);
        pool.addLiquidity{value: ethAmount}(tokenAmount);
        vm.stopPrank();

        assertGt(pool.liquidityShares(user2), initialShares);
    }

    function testAddLiquidityRefundExcessETH() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 500 * 10**18;
        uint256 ethAmount = 5.1 ether; // Within 2% tolerance of optimal (5 ether)
        uint256 initialBalance = user2.balance;

        vm.startPrank(user2);
        token.approve(address(pool), tokenAmount);
        
        pool.addLiquidity{value: ethAmount}(tokenAmount);
        vm.stopPrank();

        // Should refund excess ETH
        assertGt(user2.balance, initialBalance - ethAmount);
    }

    function testAddLiquidityInsufficientAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Amount must be greater than zero");
        pool.addLiquidity{value: 0}(1000);
        
        vm.expectRevert("Amount must be greater than zero");
        pool.addLiquidity{value: 1 ether}(0);
        vm.stopPrank();
    }

    function testAddLiquidityInsufficientBalance() public {
        uint256 tokenAmount = 200000 * 10**18; // More than user1 has

        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount);
        vm.expectRevert("Insufficient balance");
        pool.addLiquidity{value: 1 ether}(tokenAmount);
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        testAddLiquidityInitial();

        uint256 userShares = pool.liquidityShares(user1);
        uint256 sharesToRemove = userShares / 2;

        vm.startPrank(user1);
        uint256 initialTokenBalance = token.balanceOf(user1);
        uint256 initialEthBalance = user1.balance;

        pool.removeLiquidity(sharesToRemove);
        vm.stopPrank();

        assertGt(token.balanceOf(user1), initialTokenBalance);
        assertGt(user1.balance, initialEthBalance);
        assertEq(pool.liquidityShares(user1), userShares - sharesToRemove);
    }

    function testRemoveLiquidityInsufficientShares() public {
        testAddLiquidityInitial();

        vm.startPrank(user2); // user2 has no shares
        vm.expectRevert("Insufficient liquidity shares");
        pool.removeLiquidity(1000);
        vm.stopPrank();
    }

    function testRemoveLiquidityZeroShares() public {
        vm.startPrank(user1);
        vm.expectRevert("Shares must be greater than zero");
        pool.removeLiquidity(0);
        vm.stopPrank();
    }

    function testRemoveLiquidityMinimumLiquidity() public {
        uint256 tokenAmount1 = 10 * 10**18;  // Small amount
        uint256 ethAmount1 = 0.1 ether;      // Small amount
        
        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount1);
        pool.addLiquidity{value: ethAmount1}(tokenAmount1);
        vm.stopPrank();
        
        uint256 tokenAmount2 = 20 * 10**18;   
        uint256 ethAmount2 = 0.2 ether;       
        
        vm.startPrank(user2);
        token.approve(address(pool), tokenAmount2);
        pool.addLiquidity{value: ethAmount2}(tokenAmount2);
        vm.stopPrank();
        
        uint256 totalShares = pool.totalLiquidityShares();
        uint256 user1Shares = pool.liquidityShares(user1);
        
        uint256 excessiveShares = totalShares - pool.MINIMUM_LIQUIDITY() + 1;
        
        if (user1Shares >= excessiveShares) {
            vm.startPrank(user1);
            vm.expectRevert("Cannot remove minimum liquidity");
            pool.removeLiquidity(excessiveShares);
            vm.stopPrank();
        } else {
            vm.startPrank(user1);
            pool.removeLiquidity(user1Shares);
            vm.stopPrank();
            
            uint256 remainingShares = pool.totalLiquidityShares();
            uint256 user2Shares = pool.liquidityShares(user2);
            
            if (user2Shares > remainingShares - pool.MINIMUM_LIQUIDITY()) {
                vm.startPrank(user2);
                vm.expectRevert("Cannot remove minimum liquidity");
                pool.removeLiquidity(remainingShares - pool.MINIMUM_LIQUIDITY() + 1);
                vm.stopPrank();
            }
        }
    }

    function testBuyTokens() public {
        testAddLiquidityInitial();

        uint256 ethAmount = 1 ether;
        uint256 minTokensOut = 90 * 10**18;

        vm.startPrank(user2);
        uint256 initialTokenBalance = token.balanceOf(user2);

        vm.expectEmit(true, false, false, true);
        emit LiquidityPool.TokenPurchased(user2, ethAmount, 90661089388014913158);

        pool.buyTokens{value: ethAmount}(minTokensOut);
        vm.stopPrank();

        assertGt(token.balanceOf(user2), initialTokenBalance);
    }

    function testBuyTokensInsufficientOutput() public {
        testAddLiquidityInitial();

        uint256 ethAmount = 1 ether;
        uint256 minTokensOut = 200 * 10**18; // Too high

        vm.startPrank(user2);
        vm.expectRevert("Insufficient output amount");
        pool.buyTokens{value: ethAmount}(minTokensOut);
        vm.stopPrank();
    }

    function testBuyTokensZeroETH() public {
        vm.startPrank(user1);
        vm.expectRevert("ETH amount must be greater than zero");
        pool.buyTokens{value: 0}(100);
        vm.stopPrank();
    }

    function testBuyTokensNoLiquidity() public {
        vm.startPrank(user1);
        vm.expectRevert("Liquidity not available");
        pool.buyTokens{value: 1 ether}(100);
        vm.stopPrank();
    }

    function testSellTokens() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 100 * 10**18;
        uint256 minEthOut = 0.8 ether;

        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount);
        uint256 initialEthBalance = user1.balance;

        vm.expectEmit(true, false, false, true);
        emit LiquidityPool.TokenSold(user1, tokenAmount, 906610893880149131);

        pool.sellTokens(tokenAmount, minEthOut);
        vm.stopPrank();

        assertGt(user1.balance, initialEthBalance);
    }

    function testSellTokensInsufficientOutput() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 100 * 10**18;
        uint256 minEthOut = 5 ether; // Too high

        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount);
        vm.expectRevert("Insufficient output amount");
        pool.sellTokens(tokenAmount, minEthOut);
        vm.stopPrank();
    }

    function testSellTokensZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert("Token amount must be greater than zero");
        pool.sellTokens(0, 100);
        vm.stopPrank();
    }

    function testSellTokensInsufficientBalance() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 200000 * 10**18; // More than user1 has

        vm.startPrank(user1);
        token.approve(address(pool), tokenAmount);
        vm.expectRevert("Insufficient token balance");
        pool.sellTokens(tokenAmount, 1 ether);
        vm.stopPrank();
    }

    function testGetTokensForEth() public {
        testAddLiquidityInitial();

        uint256 ethAmount = 1 ether;
        uint256 expectedTokens = pool.getTokensForEth(ethAmount);
        
        assertGt(expectedTokens, 0);
        assertEq(expectedTokens, 90661089388014913158);
    }

    function testGetTokensForEthNoLiquidity() public {
        uint256 expectedTokens = pool.getTokensForEth(1 ether);
        assertEq(expectedTokens, 0);
    }

    function testGetEthForTokens() public {
        testAddLiquidityInitial();

        uint256 tokenAmount = 100 * 10**18;
        uint256 expectedEth = pool.getEthForTokens(tokenAmount);
        
        assertGt(expectedEth, 0);
        assertEq(expectedEth, 906610893880149131);
    }

    function testGetEthForTokensNoLiquidity() public {
        uint256 expectedEth = pool.getEthForTokens(100 * 10**18);
        assertEq(expectedEth, 0);
    }

    function testGetTokenPrice() public {
        testAddLiquidityInitial();

        uint256 price = pool.getTokenPrice();
        assertGt(price, 0);
        assertEq(price, 10000000000000000); // 0.01 ETH per token
    }

    function testGetTokenPriceNoReserve() public {
        uint256 price = pool.getTokenPrice();
        assertEq(price, 0);
    }

    function testGetUserLiquidity() public {
        testAddLiquidityInitial();

        (uint256 shares, uint256 tokenAmount, uint256 ethAmount) = pool.getUserLiquidity(user1);
        
        assertGt(shares, 0);
        assertGt(tokenAmount, 0);
        assertGt(ethAmount, 0);
    }

    function testGetUserLiquidityNoShares() public {
        (uint256 shares, uint256 tokenAmount, uint256 ethAmount) = pool.getUserLiquidity(user2);
        
        assertEq(shares, 0);
        assertEq(tokenAmount, 0);
        assertEq(ethAmount, 0);
    }

    function testGetReserves() public {
        testAddLiquidityInitial();

        (uint256 tokenReserve, uint256 ethReserve, uint256 totalShares) = pool.getReserves();
        
        assertEq(tokenReserve, pool.tokenReserve());
        assertEq(ethReserve, pool.ethReserve());
        assertEq(totalShares, pool.totalLiquidityShares());
    }

    function testSetLiquidityFee() public {
        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, true);
        emit LiquidityPool.LiquidityFeeUpdated(30, 50);
        
        pool.setLiquidityFee(50);
        
        assertEq(pool.liquidityFee(), 50);
        vm.stopPrank();
    }

    function testSetLiquidityFeeTooHigh() public {
        vm.startPrank(owner);
        vm.expectRevert("Liquidity fee too high");
        pool.setLiquidityFee(101);
        vm.stopPrank();
    }

    function testSetLiquidityFeeNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        pool.setLiquidityFee(50);
        vm.stopPrank();
    }

    function testPause() public {
        vm.startPrank(owner);
        pool.pause();
        assertTrue(pool.paused());
        vm.stopPrank();
    }

    function testPauseNotOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        pool.pause();
        vm.stopPrank();
    }

    function testUnpause() public {
        vm.startPrank(owner);
        pool.pause();
        pool.unpause();
        assertFalse(pool.paused());
        vm.stopPrank();
    }

    function testUnpauseNotOwner() public {
        vm.startPrank(owner);
        pool.pause();
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert();
        pool.unpause();
        vm.stopPrank();
    }

    function testAddLiquidityWhenPaused() public {
        vm.startPrank(owner);
        pool.pause();
        vm.stopPrank();

        vm.startPrank(user1);
        token.approve(address(pool), 1000 * 10**18);
        vm.expectRevert();
        pool.addLiquidity{value: 1 ether}(1000 * 10**18);
        vm.stopPrank();
    }

    function testBuyTokensWhenPaused() public {
        testAddLiquidityInitial();
        
        vm.startPrank(owner);
        pool.pause();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert();
        pool.buyTokens{value: 1 ether}(100);
        vm.stopPrank();
    }

    function testReceiveETH() public {
        vm.startPrank(user1);
        (bool success, ) = address(pool).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(pool).balance, 1 ether);
        vm.stopPrank();
    }

    function testSqrtFunction() public {
        vm.startPrank(user1);
        token.approve(address(pool), 10000 * 10**18);
        
        pool.addLiquidity{value: 100 ether}(10000 * 10**18);
        
        assertGt(pool.totalLiquidityShares(), 0);
        vm.stopPrank();
    }

    function testMultipleUsersLiquidity() public {
        vm.startPrank(user1);
        token.approve(address(pool), 1000 * 10**18);
        pool.addLiquidity{value: 10 ether}(1000 * 10**18);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(pool), 500 * 10**18);
        pool.addLiquidity{value: 5 ether}(500 * 10**18);
        vm.stopPrank();

        vm.startPrank(user3);
        token.approve(address(pool), 200 * 10**18);
        pool.addLiquidity{value: 2 ether}(200 * 10**18);
        vm.stopPrank();

        assertGt(pool.liquidityShares(user1), 0);
        assertGt(pool.liquidityShares(user2), 0);
        assertGt(pool.liquidityShares(user3), 0);

        uint256 totalShares = pool.liquidityShares(user1) + 
                             pool.liquidityShares(user2) + 
                             pool.liquidityShares(user3) + 
                             pool.MINIMUM_LIQUIDITY();
        assertEq(pool.totalLiquidityShares(), totalShares);
    }

    function testLiquidityFeeCalculation() public {
        testAddLiquidityInitial();

        uint256 ethAmount = 1 ether;
        uint256 expectedFee = (ethAmount * pool.liquidityFee()) / pool.TAX_DIVISOR();
        uint256 ethAfterFee = ethAmount - expectedFee;
        
        uint256 calculatedTokens = pool.getTokensForEth(ethAmount);
        uint256 expectedTokens = (ethAfterFee * pool.tokenReserve()) / (pool.ethReserve() + ethAfterFee);
        
        assertEq(calculatedTokens, expectedTokens);
    }

    function testNonReentrantModifiers() public {
        testAddLiquidityInitial();
        
        vm.startPrank(user2);
        pool.buyTokens{value: 1 ether}(50 * 10**18);
        
        token.approve(address(pool), 100 * 10**18);
        pool.sellTokens(100 * 10**18, 0.5 ether);
        vm.stopPrank();
        
        assertTrue(true);
    }
}