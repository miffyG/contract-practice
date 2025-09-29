// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ILiquidityPool.sol";

contract MyMeme is ERC20, ERC20Burnable, Ownable, ReentrancyGuard, Pausable {
    // 税费分配地址
    address public marketingWallet; // 营销钱包
    address public developmentWallet; // 开发钱包
    address public liquidityWallet; // 流动性钱包

    uint256 public buyTaxRate = 500; // 买入税率 5% (基数10000)
    uint256 public sellTaxRate = 800; // 卖出税率 8% (基数10000)
    uint256 public constant MAX_TAX_RATE = 1500; // 最大税率 15%
    uint256 public constant TAX_DIVISOR = 10000;

    // 税费分配比例 (总和为100)
    uint256 public marketingShare = 40; // 营销 40%
    uint256 public developmentShare = 30; // 开发 30%
    uint256 public liquidityShare = 30; // 流动性 30%

    // 流动性池合约地址
    address public liquidityPool;

    // 交易限制相关
    uint256 public maxTransactionAmount; // 单笔最大交易金额
    uint256 public dailyTransactionLimit = 10; // 每日交易次数限制，仅限制买卖代币

    mapping(address => bool) public isExcludedFromFees; // 免税白名单
    mapping(address => bool) public isExcludedFromLimits; // 交易限制白名单
    mapping(address => bool) public isBlacklisted; // 黑名单

    // 用户交易记录
    mapping(address => uint256) public dailyTransactionCount; // 每日交易计数
    mapping(address => uint256) public lastTransactionDate; // 最后交易日期

    uint256 public totalTaxCollected; // 累计收取的税费

    // 事件定义
    event TaxRateUpdated(uint256 newBuyRate, uint256 newSellRate);
    event TaxDistributed(
        uint256 marketingAmount,
        uint256 developmentAmount,
        uint256 liquidityAmount
    );
    event TransactionLimitsUpdated(uint256 maxTransaction, uint256 maxWallet);
    event ExcludedFromFeesUpdated(address indexed account, bool excluded);
    event ExcludedFromLimitsUpdated(address indexed account, bool excluded);
    event UserBlacklisted(address indexed user, bool isBlacklisted);
    event LiquidityPoolUpdated(address indexed oldPool, address indexed newPool);

    // 修饰符
    modifier notBlacklisted(address account) {
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }

    modifier checkTransactionLimits(
        address from,
        address to,
        uint256 amount
    ) {
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            require(
                amount <= maxTransactionAmount,
                "Exceeds max transaction amount"
            );

            // 检查每日交易次数限制 - 只检查发送方
            if (from != address(this) && from != address(0)) {
                _checkDailyTransactionLimit(from);
            }
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _marketingWallet,
        address _devWallet,
        address _liquidityWallet
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(
            _marketingWallet != address(0),
            "Marketing wallet cannot be zero address"
        );
        require(_devWallet != address(0), "Dev wallet cannot be zero address");
        require(
            _liquidityWallet != address(0),
            "Liquidity wallet cannot be zero address"
        );

        marketingWallet = _marketingWallet;
        developmentWallet = _devWallet;
        liquidityWallet = _liquidityWallet;

        maxTransactionAmount = (_totalSupply * 1) / 100; // 初始设置为总供应量的1%

        // 合约和合约拥有者默认加入免税和交易限制白名单
        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromLimits[owner()] = true;
        isExcludedFromLimits[address(this)] = true;

        _mint(msg.sender, _totalSupply);
    }

    // 接收ETH
    receive() external payable {}

    function _update(
        address from,
        address to,
        uint256 amount
    )
        internal
        override
        notBlacklisted(from)
        checkTransactionLimits(from, to, amount)
        whenNotPaused
    {
        super._update(from, to, amount);

        // 更新每日交易计数 - 只更新发送方的计数
        if (from != address(0) && from != address(this)) {
            _updateDailyTransactionCount(from);
        }
    }

    // 添加内部转移函数，用于税费分发等内部操作
    function _internalTransfer(
        address from,
        address to,
        uint256 amount
    ) internal {
        // 直接调用 ERC20 的 _update，绕过限制检查
        super._update(from, to, amount);
    }

    // 检查每日交易计数
    function _checkDailyTransactionLimit(address account) internal view {
        uint256 currentDate = block.timestamp / 1 days;
        if (lastTransactionDate[account] == currentDate) {
            require(
                dailyTransactionCount[account] < dailyTransactionLimit,
                "Exceeds daily transaction limit"
            );
        }
    }

    // 更新每日交易计数
    function _updateDailyTransactionCount(address account) internal {
        uint256 currentDate = block.timestamp / 1 days;
        if (lastTransactionDate[account] == currentDate) {
            dailyTransactionCount[account] += 1;
        } else {
            dailyTransactionCount[account] = 1;
            lastTransactionDate[account] = currentDate;
        }
    }

    /**
     * @dev 计算交易税费
     * @param amount 交易金额
     * @param isBuy 是否为买入交易
     * @return 税费金额
     */
    function _calculateTax(
        uint256 amount,
        bool isBuy
    ) internal view returns (uint256) {
        uint256 taxRate = isBuy ? buyTaxRate : sellTaxRate;
        return (amount * taxRate) / TAX_DIVISOR;
    }

    /**
     * @dev 分配税费到各个钱包
     * @param taxAmount 待分配的税费金额
     */
    function _distributeTax(uint256 taxAmount) internal {
        uint256 marketingAmount = (taxAmount * marketingShare) / 100;
        uint256 developmentAmount = (taxAmount * developmentShare) / 100;
        uint256 liquidityAmount = taxAmount -
            marketingAmount -
            developmentAmount; // 剩余部分给流动性

        if (marketingAmount > 0) {
            _internalTransfer(address(this), marketingWallet, marketingAmount);
        }
        if (developmentAmount > 0) {
            _internalTransfer(address(this), developmentWallet, developmentAmount);
        }
        if (liquidityAmount > 0) {
            _internalTransfer(address(this), liquidityWallet, liquidityAmount);
        }
        emit TaxDistributed(
            marketingAmount,
            developmentAmount,
            liquidityAmount
        );
    }

    /**
     * @dev 设置流动性池合约地址
     * @param _liquidityPool 流动性池合约地址
     */
    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        require(
            _liquidityPool != address(0),
            "Liquidity pool cannot be zero address"
        );
        address oldPool = liquidityPool;
        liquidityPool = _liquidityPool;

        // 将流动性池加入免税和交易限制白名单
        isExcludedFromFees[_liquidityPool] = true;
        isExcludedFromLimits[_liquidityPool] = true;

        emit LiquidityPoolUpdated(oldPool, _liquidityPool);
    }

    /**
     * @dev 获取当前代币价格 (从流动性池获取)
     * @return 每个代币的价格，单位为ETH的1e18倍
     */
    function getTokenPrice() external view returns (uint256) {
        if (liquidityPool == address(0)) return 0;
        return ILiquidityPool(liquidityPool).getTokenPrice();
    }

    /**
     * @dev 检查账户是否免税
     * @param account 要检查的账户地址
     */
    function checkExcludedFromFees(
        address account
    ) external view returns (bool) {
        return isExcludedFromFees[account];
    }

    /**
     * @dev 检查账户是否在交易限制白名单
     * @param account 要检查的账户地址
     */
    function checkExcludedFromLimits(
        address account
    ) external view returns (bool) {
        return isExcludedFromLimits[account];
    }

    /**
     * @dev 检查账户是否在黑名单
     * @param account 要检查的账户地址
     */
    function checkIsBlacklisted(address account) external view returns (bool) {
        return isBlacklisted[account];
    }

    /**
     * @dev 获取账户剩余的每日交易次数
     * @param account 要检查的账户地址
     */
    function getRemainingDailyTransactions(
        address account
    ) external view returns (uint256) {
        uint256 currentDate = block.timestamp / 1 days;
        if (lastTransactionDate[account] == currentDate) {
            return dailyTransactionLimit - dailyTransactionCount[account];
        } else {
            return dailyTransactionLimit;
        }
    }

    /**
     * @dev 获取用户在流动性池中的份额和对应的代币及ETH数量
     * @param account 要查询的用户地址
     * @return shares 用户的流动性份额
     * @return tokenAmount 用户对应的代币数量
     * @return ethAmount 用户对应的ETH数量
     */
    function getUserLiquidity(
        address account
    )
        external
        view
        returns (uint256 shares, uint256 tokenAmount, uint256 ethAmount)
    {
        if (liquidityPool == address(0)) {
            return (0, 0, 0);
        }
        return ILiquidityPool(liquidityPool).getUserLiquidity(account);
    }

    /**
     * @dev 获取流动性池的储备情况
     * @return _tokenReserve 当前代币储备
     * @return _ethReserve 当前ETH储备
     * @return _totalLiquidityShares 当前总流动性份额
     */
    function getReserves()
        external
        view
        returns (
            uint256 _tokenReserve,
            uint256 _ethReserve,
            uint256 _totalLiquidityShares
        )
    {
        if (liquidityPool == address(0)) {
            return (0, 0, 0);
        }
        return ILiquidityPool(liquidityPool).getReserves();
    }

    /**
     * @dev 设置单个免税地址
     * @param account 要设置的账户地址
     * @param excluded 是否排除在税费之外
     */
    function setExcludedFromFees(
        address account,
        bool excluded
    ) external onlyOwner {
        require(account != address(0), "Invalid address");
        isExcludedFromFees[account] = excluded;
        emit ExcludedFromFeesUpdated(account, excluded);
    }

    /**
     * @dev 批量设置免税地址
     * @param accounts 要设置的账户地址数组
     * @param excluded 是否排除在税费之外
     */
    function setExcludedFromFeesBatch(
        address[] calldata accounts,
        bool excluded
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (account != address(0)) {
                isExcludedFromFees[account] = excluded;
                emit ExcludedFromFeesUpdated(account, excluded);
            }
        }
    }

    /**
     * @dev 设置单个交易限制白名单地址
     * @param account 要设置的账户地址
     * @param excluded 是否排除在交易限制之外
     */
    function setExcludedFromLimits(
        address account,
        bool excluded
    ) external onlyOwner {
        require(account != address(0), "Invalid address");
        isExcludedFromLimits[account] = excluded;
        emit ExcludedFromLimitsUpdated(account, excluded);
    }

    /**
     * @dev 批量设置交易限制白名单地址
     * @param accounts 要设置的账户地址数组
     * @param excluded 是否排除在交易限制之外
     */
    function setExcludedFromLimitsBatch(
        address[] calldata accounts,
        bool excluded
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            if (account != address(0)) {
                isExcludedFromLimits[account] = excluded;
                emit ExcludedFromLimitsUpdated(account, excluded);
            }
        }
    }

    /**
     * @dev 同时设置免税和交易限制白名单地址
     * @param account 要设置的账户地址
     * @param excludedFromFees 是否排除在税费之外
     * @param excludedFromLimits 是否排除在交易限制之外
     */
    function setExcluded(
        address account,
        bool excludedFromFees,
        bool excludedFromLimits
    ) external onlyOwner {
        require(account != address(0), "Invalid address");
        isExcludedFromFees[account] = excludedFromFees;
        isExcludedFromLimits[account] = excludedFromLimits;
        emit ExcludedFromFeesUpdated(account, excludedFromFees);
        emit ExcludedFromLimitsUpdated(account, excludedFromLimits);
    }

    /**
     * @dev 设置交易税率
     * @param _buyTaxRate 购买税率
     * @param _sellTaxRate 卖出税率
     */
    function setTaxRates(
        uint256 _buyTaxRate,
        uint256 _sellTaxRate
    ) external onlyOwner {
        require(_buyTaxRate <= MAX_TAX_RATE, "Buy tax rate too high");
        require(_sellTaxRate <= MAX_TAX_RATE, "Sell tax rate too high");
        buyTaxRate = _buyTaxRate;
        sellTaxRate = _sellTaxRate;
        emit TaxRateUpdated(_buyTaxRate, _sellTaxRate);
    }

    /**
     * @dev 设置交易限制参数
     * @param _maxTransactionAmount 最大单笔交易金额
     * @param _dailyTransactionLimit 每日交易次数限制
     */
    function setTransactionLimits(
        uint256 _maxTransactionAmount,
        uint256 _dailyTransactionLimit
    ) external onlyOwner {
        require(
            _maxTransactionAmount > 0,
            "Max transaction amount must be greater than zero"
        );
        require(
            _dailyTransactionLimit > 0,
            "Daily transaction limit must be greater than zero"
        );
        maxTransactionAmount = _maxTransactionAmount;
        dailyTransactionLimit = _dailyTransactionLimit;
        emit TransactionLimitsUpdated(
            _maxTransactionAmount,
            _dailyTransactionLimit
        );
    }

    /**
     * @dev 设置黑名单用户
     * @param account 要设置的账户地址
     * @param blacklisted 是否黑名单
     */
    function setBlacklisted(
        address account,
        bool blacklisted
    ) external onlyOwner {
        require(account != address(0), "Invalid address");
        isBlacklisted[account] = blacklisted;
        emit UserBlacklisted(account, blacklisted);
    }

    /**
     * @dev 暂停合约
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约运行
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
