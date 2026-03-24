// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";

interface IERC20 {
    function approve(address spender, uint amount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
    function transfer(address to, uint amount) external returns (bool);
}

interface IWETH {
    function withdraw(uint wad) external;
}

interface IUniswapV2Pair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface ILendingPool {
    function liquidationCall(
        address collateral,
        address debt,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external;
}

contract LiquidationOperator {

    address constant UNISWAP_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address constant LENDING_POOL = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address constant TARGET = 0x63f6037d3e9d51ad865056BF7792029803b6eEfD;

    // sweet spot ที่กำไร
    uint256 constant debt_to_cover = 2000 * 1e6;

    function operate() external {
        IUniswapV2Pair pair = IUniswapV2Pair(UNISWAP_PAIR);

        address token0 = pair.token0();

        uint amount0Out = 0;
        uint amount1Out = 0;

        if (token0 == USDC) {
            amount0Out = debt_to_cover;
        } else {
            amount1Out = debt_to_cover;
        }

        pair.swap(amount0Out, amount1Out, address(this), "flash");
    }

    function uniswapV2Call(address, uint amount0, uint amount1, bytes calldata) external {

        uint amountUSDC = amount0 > 0 ? amount0 : amount1;

        // approve ให้ Aave
        IERC20(USDC).approve(LENDING_POOL, amountUSDC);

        // liquidation
        ILendingPool(LENDING_POOL).liquidationCall(
            WETH,
            USDC,
            TARGET,
            amountUSDC,
            false
        );

        uint wethBalance = IERC20(WETH).balanceOf(address(this));

        // get reserves
        IUniswapV2Pair pair = IUniswapV2Pair(UNISWAP_PAIR);
        (uint112 r0, uint112 r1,) = pair.getReserves();

        address token0 = pair.token0();

        uint reserveUSDC;
        uint reserveWETH;

        if (token0 == USDC) {
            reserveUSDC = r0;
            reserveWETH = r1;
        } else {
            reserveUSDC = r1;
            reserveWETH = r0;
        }

        uint amountRequired = getAmountIn(amountUSDC, reserveWETH, reserveUSDC);

        require(wethBalance >= amountRequired, "NOT ENOUGH WETH");

        // repay flash swap
        IERC20(WETH).transfer(UNISWAP_PAIR, amountRequired);

        // ===== PROFIT =====
        uint profit = IERC20(WETH).balanceOf(address(this));

        // unwrap WETH -> ETH
        IWETH(WETH).withdraw(profit);

        // send ETH to user
        payable(tx.origin).transfer(profit);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint) {
        uint numerator = reserveIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    receive() external payable {}
}
