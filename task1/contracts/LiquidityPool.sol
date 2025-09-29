// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ILiquidityPool.sol";

contract LiquidityPool is ILiquidityPool, Ownable, ReentrancyGuard, Pausable {
    IERC20 public immutable token;
    
    // AMM 流动性池相关
    uint256 public tokenReserve; // 代币储备量
    uint256 public ethReserve; // ETH储备量
    uint256 public totalLiquidityShares; // 总流动性份额
    mapping(address => uint256) public liquidityShares; // 用户流动性份额

    uint256 public constant MINIMUM_LIQUIDITY = 1000; // 最小流动性锁定量
    uint256 public liquidityFee = 30; // 流动性提供者费用 0.3% (基数10000)
    uint256 public constant TAX_DIVISOR = 10000;

    // 事件定义
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
    event ReservesUpdated(uint256 tokenReserve, uint256 ethReserve);
    event LiquidityFeeUpdated(uint256 oldFee, uint256 newFee);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "Token address cannot be zero");
        token = IERC20(_token);
    }

    // 接收ETH
    receive() external payable {}

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
        require(token.balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

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
        require(token.transferFrom(msg.sender, address(this), actualTokenAmount), "Token transfer failed");

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
        require(token.transfer(msg.sender, tokenAmount), "Token transfer failed");
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
    ) external payable nonReentrant whenNotPaused {
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

        // 更新储备
        tokenReserve -= tokensOut;
        ethReserve += msg.value;

        // 转移代币给买家
        require(token.transfer(msg.sender, tokensOut), "Token transfer failed");

        emit TokenPurchased(msg.sender, msg.value, tokensOut);
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
    ) external nonReentrant whenNotPaused {
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(
            token.balanceOf(msg.sender) >= tokenAmount,
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

        // 更新储备
        tokenReserve += tokenAmount;
        ethReserve -= ethOut;

        // 转移代币到合约
        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        // 转移ETH给卖家
        payable(msg.sender).transfer(ethOut);

        emit TokenSold(msg.sender, tokenAmount, ethOut);
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
        return (ethReserve * 1e18) / tokenReserve;
    }

    /**
     * @dev 设置流动性提供者费用
     * @param _liquidityFee 设置流动性提供者费用
     */
    function setLiquidityFee(uint256 _liquidityFee) external onlyOwner {
        require(_liquidityFee <= 100, "Liquidity fee too high"); // 最大1%
        uint256 oldFee = liquidityFee;
        liquidityFee = _liquidityFee;
        emit LiquidityFeeUpdated(oldFee, _liquidityFee);
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
