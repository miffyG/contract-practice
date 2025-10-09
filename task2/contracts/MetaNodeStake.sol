// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./MetaNode.sol";

/**
 * @title MetaNodeStake
 * @dev 基于区块链的质押系统，支持多种代币质押并分配MetaNode代币奖励
 */
contract MetaNodeStake is 
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // 角色定义
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // MetaNode代币合约
    IERC20 public MetaNode;
    
    // 每个区块产生的MetaNode奖励
    uint256 public metaNodePerBlock;
    
    // 奖励开始区块
    uint256 public startBlock;
    
    // 奖励结束区块
    uint256 public endBlock;

    /**
     * @dev 质押池结构
     */
    struct Pool {
        address stTokenAddress;        // 质押代币地址（address(0)表示ETH）
        uint256 poolWeight;           // 池权重
        uint256 lastRewardBlock;      // 最后奖励区块
        uint256 accMetaNodePerST;     // 每个质押代币累积的MetaNode数量
        uint256 stTokenAmount;        // 池中总质押代币量
        uint256 minDepositAmount;     // 最小质押金额
        uint256 unstakeLockedBlocks;  // 解除质押锁定区块数
    }

    /**
     * @dev 解质押请求结构
     */
    struct UnstakeRequest {
        uint256 amount;        // 解质押数量
        uint256 unlockBlock;   // 解锁区块号
    }

    /**
     * @dev 用户信息结构
     */
    struct User {
        uint256 stAmount;           // 质押代币数量
        uint256 finishedMetaNode;   // 已分配的MetaNode数量
        uint256 pendingMetaNode;    // 待领取的MetaNode数量
        UnstakeRequest[] requests;  // 解质押请求列表
    }

    // 质押池数组
    Pool[] public pools;
    
    // 用户信息映射 poolId => user => UserInfo
    mapping(uint256 => mapping(address => User)) public users;
    
    // 总权重
    uint256 public totalPoolWeight;

    // 事件定义
    event PoolAdded(uint256 indexed pid, address indexed stTokenAddress, uint256 poolWeight, uint256 minDepositAmount, uint256 unstakeLockedBlocks);
    event PoolUpdated(uint256 indexed pid, uint256 poolWeight, uint256 minDepositAmount, uint256 unstakeLockedBlocks);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Unstake(address indexed user, uint256 indexed pid, uint256 amount, uint256 unlockBlock);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardClaimed(address indexed user, uint256 indexed pid, uint256 reward);
    event MetaNodePerBlockUpdated(uint256 newMetaNodePerBlock);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev 初始化函数
     * @param _metaNode MetaNode代币合约地址
     * @param _metaNodePerBlock 每区块MetaNode奖励
     * @param _startBlock 开始区块
     * @param _endBlock 结束区块
     */
    function initialize(
        address _metaNode,
        uint256 _metaNodePerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        require(_metaNode != address(0), unicode"MetaNode token地址不能为零");
        require(_startBlock < _endBlock, unicode"开始区块必须小于结束区块");

        MetaNode = MetaNodeToken(_metaNode);
        metaNodePerBlock = _metaNodePerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;

        // 设置默认管理员
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /**
     * @dev 授权升级函数
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function _safeTransferETH(address _to, uint256 _amount) internal {
        (bool success, bytes memory data) = _to.call{value: _amount}("");
        require(success, "ETH transfer failed");
        if (data.length > 0) {
            // 如果有返回数据，确保调用成功
            require(abi.decode(data, (bool)), "ETH transfer failed");
        }
    }

    /**
     * @dev 添加质押池
     * @param _stTokenAddress 质押代币地址（address(0)表示ETH）
     * @param _poolWeight 池权重
     * @param _minDepositAmount 最小质押金额
     * @param _unstakeLockedBlocks 解质押锁定区块数
     */
    function addPool(
        address _stTokenAddress,
        uint256 _poolWeight,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks
    ) external onlyRole(ADMIN_ROLE) {
        require(_poolWeight > 0, "poolWeight must be greater than 0");
        require(_unstakeLockedBlocks > 0, "unstakeLockedBlocks must be greater than 0");

        // 更新所有池的奖励
        massUpdatePools();

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalPoolWeight += _poolWeight;
        
        pools.push(Pool({
            stTokenAddress: _stTokenAddress,
            poolWeight: _poolWeight,
            lastRewardBlock: lastRewardBlock,
            accMetaNodePerST: 0,
            stTokenAmount: 0,
            minDepositAmount: _minDepositAmount,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));

        uint256 poolIndex = pools.length - 1;

        emit PoolAdded(poolIndex, _stTokenAddress, _poolWeight, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @dev 更新质押池
     * @param _pid 池ID
     * @param _poolWeight 新的池权重
     * @param _minDepositAmount 新的最小质押金额
     * @param _unstakeLockedBlocks 新的解质押锁定区块数
     */
    function updatePool(
        uint256 _pid,
        uint256 _poolWeight,
        uint256 _minDepositAmount,
        uint256 _unstakeLockedBlocks
    ) external onlyRole(ADMIN_ROLE) {
        require(_pid < pools.length, "Pool does not exist");
        require(_poolWeight > 0, "poolWeight must be greater than 0");
        require(_unstakeLockedBlocks > 0, "unstakeLockedBlocks must be greater than 0");

        // 更新所有池的奖励
        massUpdatePools();

        Pool storage pool = pools[_pid];
        totalPoolWeight = totalPoolWeight - pool.poolWeight + _poolWeight;
        pool.poolWeight = _poolWeight;
        pool.minDepositAmount = _minDepositAmount;
        pool.unstakeLockedBlocks = _unstakeLockedBlocks;

        emit PoolUpdated(_pid, _poolWeight, _minDepositAmount, _unstakeLockedBlocks);
    }

    /**
     * @dev 质押代币
     * @param _pid 池ID
     * @param _amount 质押数量
     */
    function deposit(uint256 _pid, uint256 _amount) external payable nonReentrant whenNotPaused {
        require(_pid < pools.length, "Pool does not exist");
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        // 检查最小质押金额
        require(_amount >= pool.minDepositAmount, "Deposit amount is less than minimum");

        // 更新池奖励
        updatePool(_pid);

        // 如果是ETH质押
        if (pool.stTokenAddress == address(0)) {
            require(msg.value == _amount, "ETH amount does not match");
        } else {
            require(msg.value == 0, "ETH should not be sent");
            IERC20(pool.stTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }

        // 更新用户奖励
        _updateUserReward(pool, user);

        // 更新用户和池的状态
        user.stAmount += _amount;
        _updateUserFinishedReward(pool, user);
        pool.stTokenAmount += _amount;

        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @dev 申请解除质押
     * @param _pid 池ID
     * @param _amount 解除质押数量
     */
    function unstake(uint256 _pid, uint256 _amount) external nonReentrant whenNotPaused {
        require(_pid < pools.length, "pool does not exist");
        require(_amount > 0, "unstake amount must be greater than 0");

        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        require(user.stAmount >= _amount, "unstake amount exceeds staked amount");

        // 更新池奖励
        updatePool(_pid);

        // 更新用户奖励
        _updateUserReward(pool, user);

        // 更新用户和池的状态
        user.stAmount -= _amount;
        _updateUserFinishedReward(pool, user);
        
        pool.stTokenAmount -= _amount;

        // 添加解质押请求
        uint256 unlockBlock = block.number + pool.unstakeLockedBlocks;
        user.requests.push(UnstakeRequest({
            amount: _amount,
            unlockBlock: unlockBlock
        }));

        emit Unstake(msg.sender, _pid, _amount, unlockBlock);
    }

    /**
     * @dev 更新用户待领取奖励
     * @param pool 池信息
     * @param user 用户信息
     */
    function _updateUserReward(Pool storage pool, User storage user) internal {
        if (user.stAmount > 0) {
            uint256 accReward = user.stAmount * pool.accMetaNodePerST;
            uint256 normalizedReward = accReward / 1 ether;
            uint256 pending = normalizedReward - user.finishedMetaNode;
            user.pendingMetaNode += pending;
        }
    }

    /**
     * @dev 更新用户已完成奖励
     * @param pool 池信息
     * @param user 用户信息
     */
    function _updateUserFinishedReward(Pool storage pool, User storage user) internal {
        uint256 accReward = user.stAmount * pool.accMetaNodePerST;
        user.finishedMetaNode = accReward / 1 ether;
    }

    /**
     * @dev 提取已解锁的质押代币
     * @param _pid 池ID
     */
    function withdraw(uint256 _pid) external nonReentrant whenNotPaused {
        require(_pid < pools.length, "pool does not exist");
        
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];
        
        uint256 totalWithdraw = 0;
        uint256 validRequests = 0;

        // 遍历解质押请求，找出可提取的
        for (uint256 i = 0; i < user.requests.length; i++) {
            if (user.requests[i].unlockBlock <= block.number) {
                totalWithdraw += user.requests[i].amount;
            } else {
                // 保留未解锁的请求
                user.requests[validRequests] = user.requests[i];
                validRequests++;
            }
        }

        require(totalWithdraw > 0, "No tokens available for withdrawal");

        // 更新请求数组长度
        for (uint256 i = user.requests.length; i > validRequests; i--) {
            user.requests.pop();
        }

        // 转移代币
        if (pool.stTokenAddress == address(0)) {
            // 转移ETH
            _safeTransferETH(msg.sender, totalWithdraw);
        } else {
            // 转移ERC20代币
            IERC20(pool.stTokenAddress).safeTransfer(msg.sender, totalWithdraw);
        }

        emit Withdraw(msg.sender, _pid, totalWithdraw);
    }

    /**
     * @dev 领取奖励
     * @param _pid 池ID
     */
    function claimReward(uint256 _pid) external nonReentrant whenNotPaused {
        require(_pid < pools.length, "Pool does not exist");
        
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][msg.sender];

        // 更新池奖励
        updatePool(_pid);

        // 计算总奖励
        uint256 totalReward = _calculateTotalReward(pool, user);
        require(totalReward > 0, "No rewards available for claim");

        // 重置用户奖励状态
        user.pendingMetaNode = 0;
        _updateUserFinishedReward(pool, user);

        // 转移MetaNode代币
        MetaNode.transfer(msg.sender, totalReward);

        emit RewardClaimed(msg.sender, _pid, totalReward);
    }

    /**
     * @dev 计算用户总奖励
     * @param pool 池信息
     * @param user 用户信息
     * @return 总奖励
     */
    function _calculateTotalReward(Pool storage pool, User storage user) internal view returns (uint256) {
        uint256 accReward = user.stAmount * pool.accMetaNodePerST;
        uint256 normalizedReward = accReward / 1 ether;
        uint256 pending = normalizedReward - user.finishedMetaNode;
        return user.pendingMetaNode + pending;
    }

    /**
     * @dev 更新指定池的奖励
     * @param _pid 池ID
     */
    function updatePool(uint256 _pid) public {
        require(_pid < pools.length, "Pool does not exist");
        
        Pool storage pool = pools[_pid];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.stTokenAmount == 0 || pool.poolWeight == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 endBlockForReward = block.number < endBlock ? block.number : endBlock;
        if (pool.lastRewardBlock >= endBlockForReward) {
            return;
        }

        uint256 rewardPerToken = _calculateRewardPerToken(pool, endBlockForReward);
        pool.accMetaNodePerST += rewardPerToken;
        pool.lastRewardBlock = endBlockForReward;
    }

    /**
     * @dev 计算每个代币的奖励
     * @param pool 池信息
     * @param endBlockForReward 奖励结束区块
     * @return 每个代币的奖励
     */
    function _calculateRewardPerToken(Pool storage pool, uint256 endBlockForReward) internal view returns (uint256) {
        uint256 blockCount = endBlockForReward - pool.lastRewardBlock;
        uint256 baseReward = blockCount * metaNodePerBlock;
        uint256 weightedReward = baseReward * pool.poolWeight;
        uint256 metaNodeReward = weightedReward / totalPoolWeight;
        uint256 scaledReward = metaNodeReward * 1 ether;
        return scaledReward / pool.stTokenAmount;
    }

    /**
     * @dev 批量更新所有池的奖励
     */
    function massUpdatePools() public {
        for (uint256 pid = 0; pid < pools.length; pid++) {
            updatePool(pid);
        }
    }

    /**
     * @dev 计算池的最新累积奖励
     * @param pool 池信息
     * @return 最新的累积奖励
     */
    function _calculateUpdatedAccMetaNode(Pool storage pool) internal view returns (uint256) {
        if (block.number <= pool.lastRewardBlock || pool.stTokenAmount == 0 || pool.poolWeight == 0) {
            return pool.accMetaNodePerST;
        }

        uint256 endBlockForReward = block.number < endBlock ? block.number : endBlock;
        if (pool.lastRewardBlock >= endBlockForReward) {
            return pool.accMetaNodePerST;
        }

        uint256 rewardPerToken = _calculateRewardPerTokenSafe(pool, endBlockForReward);
        return pool.accMetaNodePerST + rewardPerToken;
    }

    /**
     * @dev 安全计算每个代币的奖励（不会revert）
     * @param pool 池信息
     * @param endBlockForReward 奖励结束区块
     * @return 每个代币的奖励，如果计算失败返回0
     */
    function _calculateRewardPerTokenSafe(Pool storage pool, uint256 endBlockForReward) internal view returns (uint256) {
        uint256 blockCount = endBlockForReward - pool.lastRewardBlock;
        uint256 baseReward = blockCount * metaNodePerBlock;
        uint256 weightedReward = baseReward * pool.poolWeight;
        uint256 metaNodeReward = weightedReward / totalPoolWeight;
        uint256 scaledReward = metaNodeReward * 1 ether;
        return scaledReward / pool.stTokenAmount;
    }

    /**
     * @dev 获取用户待领取奖励
     * @param _pid 池ID
     * @param _user 用户地址
     * @return 待领取奖励数量
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        require(_pid < pools.length, "Pool does not exist");
        
        Pool storage pool = pools[_pid];
        User storage user = users[_pid][_user];
        
        // 获取最新的累积奖励
        uint256 accMetaNodePerST = _calculateUpdatedAccMetaNode(pool);
        
        // 计算用户的累积奖励
        uint256 accReward = user.stAmount * accMetaNodePerST;
        uint256 normalizedReward = accReward / 1 ether;
        uint256 pending = normalizedReward - user.finishedMetaNode;
        return user.pendingMetaNode + pending;
    }

    /**
     * @dev 获取用户解质押请求数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @return 请求数量
     */
    function getUserUnstakeRequestCount(uint256 _pid, address _user) external view returns (uint256) {
        return users[_pid][_user].requests.length;
    }

    /**
     * @dev 获取用户指定的解质押请求
     * @param _pid 池ID
     * @param _user 用户地址
     * @param _index 请求索引
     * @return amount 解质押数量
     * @return unlockBlock 解锁区块号
     */
    function getUserUnstakeRequest(uint256 _pid, address _user, uint256 _index) 
        external 
        view 
        returns (uint256 amount, uint256 unlockBlock) 
    {
        require(_index < users[_pid][_user].requests.length, "Unstake request does not exist");
        UnstakeRequest storage request = users[_pid][_user].requests[_index];
        return (request.amount, request.unlockBlock);
    }

    /**
     * @dev 获取用户可提取的代币数量
     * @param _pid 池ID
     * @param _user 用户地址
     * @return 可提取数量
     */
    function getWithdrawableAmount(uint256 _pid, address _user) external view returns (uint256) {
        User storage user = users[_pid][_user];
        uint256 withdrawable = 0;
        
        for (uint256 i = 0; i < user.requests.length; i++) {
            if (user.requests[i].unlockBlock <= block.number) {
                withdrawable += user.requests[i].amount;
            }
        }
        
        return withdrawable;
    }

    /**
     * @dev 获取池数量
     * @return 池数量
     */
    function poolLength() external view returns (uint256) {
        return pools.length;
    }

    /**
     * @dev 更新每区块MetaNode奖励 (仅管理员)
     * @param _metaNodePerBlock 新的每区块奖励
     */
    function updateMetaNodePerBlock(uint256 _metaNodePerBlock) external onlyRole(ADMIN_ROLE) {
        massUpdatePools();
        metaNodePerBlock = _metaNodePerBlock;
        emit MetaNodePerBlockUpdated(_metaNodePerBlock);
    }

    /**
     * @dev 暂停合约 (仅管理员)
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev 恢复合约 (仅管理员)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev 紧急提取函数 (仅管理员，仅在紧急情况下使用)
     * @param _token 代币地址（address(0)表示ETH）
     * @param _amount 提取数量
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        if (_token == address(0)) {
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        }
    }
}