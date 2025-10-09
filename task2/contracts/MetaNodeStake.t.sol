// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MetaNodeStake} from "./MetaNodeStake.sol";
import {MetaNodeToken} from "./MetaNode.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10**18);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MetaNodeStakeTest is Test {
    MetaNodeStake public metaNodeStake;
    MetaNodeToken public metaNode;
    MockERC20 public stakeToken;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public admin = address(0x4);

    uint256 public constant METANODE_PER_BLOCK = 100 * 10**18;
    uint256 public constant START_BLOCK = 100;
    uint256 public constant END_BLOCK = 1000;
    uint256 public constant POOL_WEIGHT = 100;
    uint256 public constant MIN_DEPOSIT = 1 * 10**18;
    uint256 public constant UNSTAKE_LOCKED_BLOCKS = 10;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy MetaNode token
        metaNode = new MetaNodeToken();
        
        // Deploy stake token
        stakeToken = new MockERC20("Stake Token", "STK");
        
        // Deploy MetaNodeStake implementation
        MetaNodeStake implementation = new MetaNodeStake();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            MetaNodeStake.initialize.selector,
            address(metaNode),
            METANODE_PER_BLOCK,
            START_BLOCK,
            END_BLOCK
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        metaNodeStake = MetaNodeStake(address(proxy));
        
        // Transfer tokens to stake contract for rewards
        metaNode.transfer(address(metaNodeStake), 10000000 * 10**18);
        
        // Setup users with tokens
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        stakeToken.mint(user1, 1000 * 10**18);
        stakeToken.mint(user2, 1000 * 10**18);
        
        vm.stopPrank();
    }

    function testInitialize() view public {
        assertEq(address(metaNodeStake.MetaNode()), address(metaNode));
        assertEq(metaNodeStake.metaNodePerBlock(), METANODE_PER_BLOCK);
        assertEq(metaNodeStake.startBlock(), START_BLOCK);
        assertEq(metaNodeStake.endBlock(), END_BLOCK);
        assertTrue(metaNodeStake.hasRole(metaNodeStake.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testAddPool() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        assertEq(metaNodeStake.poolLength(), 1);
        assertEq(metaNodeStake.totalPoolWeight(), POOL_WEIGHT);
        
        (address stTokenAddress, uint256 poolWeight, , , uint256 stTokenAmount, uint256 minDepositAmount, uint256 unstakeLockedBlocks) = metaNodeStake.pools(0);
        assertEq(stTokenAddress, address(stakeToken));
        assertEq(poolWeight, POOL_WEIGHT);
        assertEq(stTokenAmount, 0);
        assertEq(minDepositAmount, MIN_DEPOSIT);
        assertEq(unstakeLockedBlocks, UNSTAKE_LOCKED_BLOCKS);
    }

    function testAddPoolETH() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(0), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        (address stTokenAddress, , , , , , ) = metaNodeStake.pools(0);
        assertEq(stTokenAddress, address(0));
    }

    function testAddPoolOnlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
    }

    function testUpdatePool() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 newWeight = 200;
        uint256 newMinDeposit = 2 * 10**18;
        uint256 newUnstakeLocked = 20;
        
        vm.prank(owner);
        metaNodeStake.updatePool(0, newWeight, newMinDeposit, newUnstakeLocked);
        
        (,uint256 poolWeight, , , , uint256 minDepositAmount, uint256 unstakeLockedBlocks) = metaNodeStake.pools(0);
        assertEq(poolWeight, newWeight);
        assertEq(minDepositAmount, newMinDeposit);
        assertEq(unstakeLockedBlocks, newUnstakeLocked);
        assertEq(metaNodeStake.totalPoolWeight(), newWeight);
    }

    function testDepositERC20() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        vm.stopPrank();
        
        (uint256 stAmount, , ) = metaNodeStake.users(0, user1);
        assertEq(stAmount, depositAmount);
        
        (, , , , uint256 stTokenAmount, , ) = metaNodeStake.pools(0);
        assertEq(stTokenAmount, depositAmount);
    }

    function testDepositETH() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(0), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 5 ether;
        
        vm.prank(user1);
        metaNodeStake.deposit{value: depositAmount}(0, depositAmount);
        
        (uint256 stAmount, ,) = metaNodeStake.users(0, user1);
        assertEq(stAmount, depositAmount);
    }

    function testDepositMinimumAmount() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = MIN_DEPOSIT - 1;
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        vm.expectRevert("Deposit amount is less than minimum");
        metaNodeStake.deposit(0, depositAmount);
        vm.stopPrank();
    }

    function testUnstake() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        uint256 unstakeAmount = 3 * 10**18;
        
        // Deposit first
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        
        // Unstake
        metaNodeStake.unstake(0, unstakeAmount);
        vm.stopPrank();
        
        (uint256 stAmount, ,) = metaNodeStake.users(0, user1);
        assertEq(stAmount, depositAmount - unstakeAmount);
        
        assertEq(metaNodeStake.getUserUnstakeRequestCount(0, user1), 1);
        
        (uint256 amount, uint256 unlockBlock) = metaNodeStake.getUserUnstakeRequest(0, user1, 0);
        assertEq(amount, unstakeAmount);
        assertEq(unlockBlock, block.number + UNSTAKE_LOCKED_BLOCKS);
    }

    function testUnstakeExceedsBalance() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        uint256 unstakeAmount = 15 * 10**18;
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        
        vm.expectRevert("unstake amount exceeds staked amount");
        metaNodeStake.unstake(0, unstakeAmount);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        uint256 unstakeAmount = 3 * 10**18;
        
        // Deposit and unstake
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        metaNodeStake.unstake(0, unstakeAmount);
        
        // Fast forward blocks
        vm.roll(block.number + UNSTAKE_LOCKED_BLOCKS + 1);
        
        uint256 balanceBefore = stakeToken.balanceOf(user1);
        metaNodeStake.withdraw(0);
        uint256 balanceAfter = stakeToken.balanceOf(user1);
        
        assertEq(balanceAfter - balanceBefore, unstakeAmount);
        assertEq(metaNodeStake.getUserUnstakeRequestCount(0, user1), 0);
        vm.stopPrank();
    }

    function testWithdrawNotReady() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        uint256 unstakeAmount = 3 * 10**18;
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        metaNodeStake.unstake(0, unstakeAmount);
        
        vm.expectRevert("No tokens available for withdrawal");
        metaNodeStake.withdraw(0);
        vm.stopPrank();
    }

    function testClaimReward() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        
        // Move to start block
        vm.roll(START_BLOCK);
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        
        // Fast forward some blocks to generate rewards
        vm.roll(START_BLOCK + 10);
        
        uint256 pendingReward = metaNodeStake.pendingReward(0, user1);
        assertTrue(pendingReward > 0);
        
        uint256 balanceBefore = metaNode.balanceOf(user1);
        metaNodeStake.claimReward(0);
        uint256 balanceAfter = metaNode.balanceOf(user1);
        
        assertEq(balanceAfter - balanceBefore, pendingReward);
        vm.stopPrank();
    }

    function testPendingReward() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        
        vm.roll(START_BLOCK);
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        vm.stopPrank();
        
        // At start, no pending rewards
        assertEq(metaNodeStake.pendingReward(0, user1), 0);
        
        // After some blocks, should have rewards
        vm.roll(START_BLOCK + 5);
        uint256 pending = metaNodeStake.pendingReward(0, user1);
        assertTrue(pending > 0);
        
        // Expected reward: blocks * metaNodePerBlock * poolWeight / totalPoolWeight
        uint256 expectedReward = 5 * METANODE_PER_BLOCK * POOL_WEIGHT / metaNodeStake.totalPoolWeight();
        assertEq(pending, expectedReward);
    }

    function testGetWithdrawableAmount() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        uint256 depositAmount = 10 * 10**18;
        uint256 unstakeAmount = 3 * 10**18;
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), depositAmount);
        metaNodeStake.deposit(0, depositAmount);
        metaNodeStake.unstake(0, unstakeAmount);
        
        // Before unlock, withdrawable should be 0
        assertEq(metaNodeStake.getWithdrawableAmount(0, user1), 0);
        
        // After unlock, withdrawable should be unstake amount
        vm.roll(block.number + UNSTAKE_LOCKED_BLOCKS + 1);
        assertEq(metaNodeStake.getWithdrawableAmount(0, user1), unstakeAmount);
        vm.stopPrank();
    }

    function testUpdateMetaNodePerBlock() public {
        uint256 newRate = 200 * 10**18;
        
        vm.prank(owner);
        metaNodeStake.updateMetaNodePerBlock(newRate);
        
        assertEq(metaNodeStake.metaNodePerBlock(), newRate);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        metaNodeStake.pause();
        assertTrue(metaNodeStake.paused());
        
        // Should not be able to deposit when paused
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), MIN_DEPOSIT);
        vm.expectRevert();
        metaNodeStake.deposit(0, MIN_DEPOSIT);
        vm.stopPrank();
        
        vm.prank(owner);
        metaNodeStake.unpause();
        assertFalse(metaNodeStake.paused());
    }

    function testEmergencyWithdraw() public {
        // Send some tokens to the contract
        vm.prank(owner);
        stakeToken.transfer(address(metaNodeStake), 100 * 10**18);
        
        uint256 balanceBefore = stakeToken.balanceOf(owner);
        
        vm.prank(owner);
        metaNodeStake.emergencyWithdraw(address(stakeToken), 100 * 10**18);
        
        uint256 balanceAfter = stakeToken.balanceOf(owner);
        assertEq(balanceAfter - balanceBefore, 100 * 10**18);
    }

    function testEmergencyWithdrawETH() public {
        // Send some ETH to the contract
        vm.deal(address(metaNodeStake), 10 ether);
        
        uint256 balanceBefore = owner.balance;
        
        vm.prank(owner);
        metaNodeStake.emergencyWithdraw(address(0), 5 ether);
        
        uint256 balanceAfter = owner.balance;
        assertEq(balanceAfter - balanceBefore, 5 ether);
    }

    function testMultipleUsersRewards() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        vm.roll(START_BLOCK);
        
        // User1 deposits
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), 10 * 10**18);
        metaNodeStake.deposit(0, 10 * 10**18);
        vm.stopPrank();
        
        vm.roll(START_BLOCK + 5);
        
        // User2 deposits
        vm.startPrank(user2);
        stakeToken.approve(address(metaNodeStake), 10 * 10**18);
        metaNodeStake.deposit(0, 10 * 10**18);
        vm.stopPrank();
        
        vm.roll(START_BLOCK + 10);
        
        uint256 pending1 = metaNodeStake.pendingReward(0, user1);
        uint256 pending2 = metaNodeStake.pendingReward(0, user2);
        
        // User1 should have more rewards as they staked earlier
        assertTrue(pending1 > pending2);
    }

    function testRewardsAfterEndBlock() public {
        vm.prank(owner);
        metaNodeStake.addPool(address(stakeToken), POOL_WEIGHT, MIN_DEPOSIT, UNSTAKE_LOCKED_BLOCKS);
        
        vm.roll(START_BLOCK);
        
        vm.startPrank(user1);
        stakeToken.approve(address(metaNodeStake), 10 * 10**18);
        metaNodeStake.deposit(0, 10 * 10**18);
        vm.stopPrank();
        
        // Move past end block
        vm.roll(END_BLOCK + 10);
        
        uint256 pending1 = metaNodeStake.pendingReward(0, user1);
        
        // Move further past end block
        vm.roll(END_BLOCK + 20);
        
        uint256 pending2 = metaNodeStake.pendingReward(0, user1);
        
        // Rewards should not increase after end block
        assertEq(pending1, pending2);
    }
}