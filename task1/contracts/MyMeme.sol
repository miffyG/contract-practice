// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

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

    // AMM 流动性池相关
    uint256 public tokenReserve; // 代币储备量
    uint256 public ethReserve; // ETH储备量
    uint256 public totalLiquidityShares; // 总流动性份额
    mapping(address => uint256) public liquidityShares; // 用户流动性份额

    uint256 public constant MINIMUM_LIQUIDITY = 1000; // 最小流动性锁定量
    uint256 public liquidityFee = 30; // 流动性提供者费用 0.3% (基数10000)

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
    event LiquidityAdded(
        address indexed user,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 shares
    );
    event LiquidityRemoved(
        address indexed user,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 shares
    );
    event TokenPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event TokenSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 ethAmount
    );
    event TransactionLimitsUpdated(uint256 maxTransaction, uint256 maxWallet);
    event ExcludedFromFeesUpdated(address indexed account, bool excluded);
    event ExcludedFromLimitsUpdated(address indexed account, bool excluded);
    event UserBlacklisted(address indexed user, bool isBlacklisted);
    event ReservesUpdated(uint256 tokenReserve, uint256 ethReserve);

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

            // 检查每日交易次数限制
            if (from != address(this) && to != address(this)) {
                _checkDailyTransactionLimit(from);
                if (from != to) {
                    _checkDailyTransactionLimit(to);
                }
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
        notBlacklisted(to)
        checkTransactionLimits(from, to, amount)
        whenNotPaused
    {
        super._update(from, to, amount);

        // 更新每日交易计数
        _updateDailyTransactionCount(from);
        if (from != to) {
            _updateDailyTransactionCount(to);
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
     * @dev 计算平方根 (用于初始流动性计算)
     * @param x 输入值
     * @return y 平方根
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @dev 添加流动性
     * @param tokenAmount 添加到流动性池的金额
     */
    function addLiquidity(
        uint256 tokenAmount
    ) external payable nonReentrant whenNotPaused {
        require(
            tokenAmount > 0 && msg.value > 0,
            "Amount must be greater than zero"
        );
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        uint256 shares;
        uint256 actualTokenAmount = tokenAmount;
        uint256 actualEthAmount = msg.value;

        if (totalLiquidityShares == 0) {
            // 初始流动性
            shares = _sqrt(tokenAmount * msg.value) - MINIMUM_LIQUIDITY;
            require(shares > 0, "Insufficient liquidity minted");

            // 锁定最小流动性
            liquidityShares[address(0)] = MINIMUM_LIQUIDITY;
            liquidityShares[msg.sender] = shares;
            totalLiquidityShares = shares + MINIMUM_LIQUIDITY;

            tokenReserve = tokenAmount;
            ethReserve = msg.value;
        } else {
            // 计算最优比例
            uint256 ethOptimal = (tokenAmount * ethReserve) / tokenReserve;
            uint256 tokenOptimal = (msg.value * tokenReserve) / ethReserve;

            if (ethOptimal <= msg.value) {
                require(
                    ethOptimal >= (msg.value * 98) / 100,
                    "Insufficient ETH amount"
                );
                shares = (tokenAmount * totalLiquidityShares) / tokenReserve;
                actualEthAmount = ethOptimal;

                // 退还多余的ETH
                if (msg.value > ethOptimal) {
                    payable(msg.sender).transfer(msg.value - ethOptimal);
                }
            } else {
                require(
                    tokenOptimal >= (tokenAmount * 98) / 100,
                    "Insufficient token amount"
                );
                shares = (msg.value * totalLiquidityShares) / ethReserve;
                actualTokenAmount = tokenOptimal;
            }

            require(shares > 0, "Insufficient liquidity minted");

            // 更新流动性份额和总份额
            liquidityShares[msg.sender] += shares;
            totalLiquidityShares += shares;

            // 更新储备
            tokenReserve += actualTokenAmount;
            ethReserve += actualEthAmount;
        }

        // 转移代币到合约
        _internalTransfer(msg.sender, address(this), actualTokenAmount);

        emit LiquidityAdded(
            msg.sender,
            actualTokenAmount,
            actualEthAmount,
            shares
        );
        emit ReservesUpdated(tokenReserve, ethReserve);
    }

    /**
     * @dev 移除流动性
     * @param shares 从流动性池移除的份额
     */
    function removeLiquidity(
        uint256 shares
    ) external nonReentrant whenNotPaused {
        require(shares > 0, "Shares must be greater than zero");
        require(
            liquidityShares[msg.sender] >= shares,
            "Insufficient liquidity shares"
        );
        require(totalLiquidityShares > 0, "No liquidity available");

        require(
            shares <= totalLiquidityShares - MINIMUM_LIQUIDITY,
            "Cannot remove minimum liquidity"
        );

        uint256 tokenAmount = (shares * tokenReserve) / totalLiquidityShares;
        uint256 ethAmount = (shares * ethReserve) / totalLiquidityShares;

        require(
            tokenAmount > 0 && ethAmount > 0,
            "Insufficient liquidity burned"
        );

        liquidityShares[msg.sender] -= shares;
        totalLiquidityShares -= shares;
        tokenReserve -= tokenAmount;
        ethReserve -= ethAmount;

        // 转移代币和ETH给用户
        _internalTransfer(address(this), msg.sender, tokenAmount);
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed when removing liquidity");

        emit LiquidityRemoved(msg.sender, tokenAmount, ethAmount, shares);
        emit ReservesUpdated(tokenReserve, ethReserve);
    }

    /**
     * @dev 购买代币
     * @param minTokensOut 最小期望获得的代币数量
     */
    function buyTokens(
        uint256 minTokensOut
    ) external payable nonReentrant whenNotPaused notBlacklisted(msg.sender) {
        require(msg.value > 0, "ETH amount must be greater than zero");
        require(tokenReserve > 0 && ethReserve > 0, "Liquidity not available");

        // 计算流动性费用
        uint256 ethAfterLiquidityFee = msg.value -
            (msg.value * liquidityFee) /
            TAX_DIVISOR;

        // 计算购买的代币数量 (恒定乘积公式)
        uint256 tokensOut = (ethAfterLiquidityFee * tokenReserve) /
            (ethReserve + ethAfterLiquidityFee);

        require(tokensOut >= minTokensOut, "Insufficient output amount");
        require(tokensOut < tokenReserve, "Insufficient token reserve");

        // 计算税费
        uint256 taxAmount = 0;
        uint256 finalTokensOut = tokensOut;

        if (!isExcludedFromFees[msg.sender]) {
            taxAmount = _calculateTax(msg.value, true); // 基于ETH金额计算税费
            if (taxAmount > 0) {
                _distributeTax(taxAmount);
                totalTaxCollected += taxAmount;
            }
        }

        // 更新储备
        tokenReserve -= tokensOut;
        ethReserve += msg.value;

        // 转移代币给买家
        _update(address(this), msg.sender, finalTokensOut);

        emit TokenPurchased(msg.sender, msg.value, finalTokensOut);
        emit ReservesUpdated(tokenReserve, ethReserve);
    }

    /**
     * @dev 卖出代币
     * @param tokenAmount 卖出的代币数量
     * @param minEthOut 最小期望获得的ETH数量
     */
    function sellTokens(
        uint256 tokenAmount,
        uint256 minEthOut
    ) external nonReentrant whenNotPaused notBlacklisted(msg.sender) {
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(
            balanceOf(msg.sender) >= tokenAmount,
            "Insufficient token balance"
        );
        require(tokenReserve > 0 && ethReserve > 0, "Liquidity not available");

        // 计算流动性费用后的代币数量
        uint256 tokensAfterLiquidityFee = tokenAmount -
            (tokenAmount * liquidityFee) /
            TAX_DIVISOR;

        // 计算卖出的ETH数量 (恒定乘积公式)
        uint256 ethOut = (tokensAfterLiquidityFee * ethReserve) /
            (tokenReserve + tokensAfterLiquidityFee);

        require(ethOut >= minEthOut, "Insufficient output amount");
        require(ethOut < ethReserve, "Insufficient ETH reserve");

        // 计算税费
        uint256 taxAmount = 0;
        uint256 finalEthOut = ethOut;

        if (!isExcludedFromFees[msg.sender]) {
            taxAmount = _calculateTax(ethOut, false); // 基于ETH金额计算税费
            if (taxAmount > 0) {
                finalEthOut -= taxAmount; // 从输出中扣除税费
                _distributeTax(taxAmount);
                totalTaxCollected += taxAmount;
            }
        }

        // 更新储备
        tokenReserve += tokenAmount;
        ethReserve -= ethOut;

        // 转移代币到合约
        _update(msg.sender, address(this), tokenAmount);
        // 转移ETH给卖家
        payable(msg.sender).transfer(finalEthOut);

        emit TokenSold(msg.sender, tokenAmount, finalEthOut);
        emit ReservesUpdated(tokenReserve, ethReserve);
    }

    /**
     * @dev 获取指定ETH数量可以兑换的代币数量
     * @param ethAmount 要兑换的ETH数量
     */
    function getTokensForEth(
        uint256 ethAmount
    ) external view returns (uint256) {
        if (tokenReserve == 0 || ethReserve == 0) return 0;

        uint256 ethAfterLiquidityFee = ethAmount -
            (ethAmount * liquidityFee) /
            TAX_DIVISOR;
        return
            (ethAfterLiquidityFee * tokenReserve) /
            (ethReserve + ethAfterLiquidityFee);
    }

    /**
     * @dev 获取指定代币数量可以兑换的ETH数量
     * @param tokenAmount 要兑换的代币数量
     */
    function getEthForTokens(
        uint256 tokenAmount
    ) external view returns (uint256) {
        if (tokenReserve == 0 || ethReserve == 0) return 0;
        uint256 tokensAfterLiquidityFee = tokenAmount -
            (tokenAmount * liquidityFee) /
            TAX_DIVISOR;
        return
            (tokensAfterLiquidityFee * ethReserve) /
            (tokenReserve + tokensAfterLiquidityFee);
    }

    /**
     * @dev 获取当前代币价格 (以ETH计价)
     * @return 每个代币的价格，单位为ETH的1e18倍
     */
    function getTokenPrice() external view returns (uint256) {
        if (tokenReserve == 0) return 0;
        return (ethReserve * 1e18) / tokenReserve; // 返回每个代币的价格，单位为ETH的1e18倍
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
     * @dev 设置流动性提供者费用
     * @param _liquidityFee 设置流动性提供者费用
     */
    function setLiquidityFee(uint256 _liquidityFee) external onlyOwner {
        require(_liquidityFee <= 100, "Liquidity fee too high"); // 最大1%
        liquidityFee = _liquidityFee;
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
        shares = liquidityShares[account];
        if (totalLiquidityShares > 0) {
            tokenAmount = (shares * tokenReserve) / totalLiquidityShares;
            ethAmount = (shares * ethReserve) / totalLiquidityShares;
        } else {
            tokenAmount = 0;
            ethAmount = 0;
        }
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
        _tokenReserve = tokenReserve;
        _ethReserve = ethReserve;
        _totalLiquidityShares = totalLiquidityShares;
    }
}
