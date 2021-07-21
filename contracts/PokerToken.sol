// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(address token, uint256 amountTokenDesired, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
    function removeLiquidityETH(address token, uint256 liquidity, uint256 amountTokenMin, uint256 amountETHMin, address to, uint256 deadline) external returns (uint256 amountToken, uint256 amountETH);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline) external;
}

contract PokerToken is Ownable, ERC20, ERC20Burnable {
    using Address for address;

    uint256 public constant MAX_SUPPLY = 21_000_000e18;

    IUniswapV2Router02 public constant uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    address public uniswapV2Pair;

    struct FeeRate {
        uint8 burn;
        uint8 liquidity;
        uint8 reward;
    }

    FeeRate public feeRate;

    uint256 public totalLiquidityFee;

    uint256 public totalShares;
    uint256 public totalReleased;

    mapping(address => uint256) public shares;
    mapping(address => uint256) public released;

    event Released(address indexed account, uint256 amount);

    constructor() ERC20("Poker Token", "PK") {
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        feeRate.burn = 3;
        feeRate.liquidity = 3;
        feeRate.reward = 4;
    }

    receive() external payable {
    }

    function setFeeRate(uint8 burnRate, uint8 liquidityRate, uint8 rewardRate) external onlyOwner {
        require(burnRate + liquidityRate + rewardRate <= 100, "Invalid fee rate");

        feeRate.burn = burnRate;
        feeRate.liquidity = liquidityRate;
        feeRate.reward = rewardRate;
    }

    function releasable(address account) public view returns (uint256) {
        uint256 totalReceived = (balanceOf(address(this)) + totalReleased - totalLiquidityFee);
        if (totalReceived > 0 && totalShares > 0) {
            return totalReceived * shares[account] / totalShares - released[account];
        }
        return 0;
    }

    function release() external {
        address account = _msgSender();

        uint256 amount = releasable(account);
        if (amount > 0) {
            released[account] += amount;
            totalReleased += amount;

            _transfer(address(this), account, amount);

            emit Released(account, amount);
        }
    }

    function mint(address account, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");

        _mint(account, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (feeRate.burn > 0 || feeRate.liquidity > 0 || feeRate.reward > 0) {
            if ((sender == address(uniswapV2Router) || sender == uniswapV2Pair) && recipient != owner() && !recipient.isContract()) {
                shares[recipient] += amount;
                totalShares += amount;
            }
            if (sender != owner() && !sender.isContract() && (recipient == address(uniswapV2Router) || recipient == uniswapV2Pair)) {
                (uint256 burnFee, uint256 liquidityFee, uint256 rewardFee) = _calculateFee(amount);

                uint256 totalFee = burnFee + liquidityFee + rewardFee;
                super._transfer(sender, address(this), totalFee);

                _burn(address(this), burnFee);
                _addLiquidity(liquidityFee);
            }
        }
        super._transfer(sender, recipient, amount);
    }

    function _addLiquidity(uint256 amount) private {
        totalLiquidityFee += amount;
        if (totalLiquidityFee >= 1e18) {
            _approve(address(this), address(uniswapV2Router), totalLiquidityFee);

            uint256 liquidityAmount = totalLiquidityFee / 2;
            totalLiquidityFee = 0;

            uint256 initialBalance = address(this).balance;

            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = uniswapV2Router.WETH();

            uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(liquidityAmount, 0, path, address(this), block.timestamp);

            uint256 ethAmount = address(this).balance - initialBalance;
            uniswapV2Router.addLiquidityETH{value: ethAmount}(address(this), liquidityAmount, 0, 0, owner(), block.timestamp);
        }
    }

    function _calculateFee(uint256 amount) private view returns (uint256 burnFee, uint256 liquidityFee, uint256 rewardFee) {
        return (amount * feeRate.burn / 100, amount * feeRate.liquidity / 100, amount * feeRate.reward / 100);
    }
}
