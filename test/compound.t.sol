// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../script/deploy.s.sol";

contract CompoundTest is Test, Deploy {
    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint collateralFactorMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        // Whether or not this market receives COMP
        bool isComped;
    }

    address public user1;
    address public user2;
    uint256 initialCErc20Balance;
    CErc20Delegator public cTokenA;
    CErc20Delegator public cTokenB;
    // ComptrollerInterface public unitroller;
    Comptroller public unitroller;
    SimplePriceOracle public priceOracle;
    MyErc20 public TokenA;
    MyErc20 public TokenB;

    function setUp() public override {
        super.setUp();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        cTokenA = CErc20Delegator(cTokenAAddress);
        cTokenB = CErc20Delegator(cTokenBAddress);
        priceOracle = SimplePriceOracle(oracleAddress);
        unitroller = Comptroller(unitrollerAddress);
        TokenA = MyErc20(TokenAAddress);
        TokenB = MyErc20(TokenBAddress);
    }

    function user1_borrow_tokenA() public {
        deal(address(TokenBAddress), user1, 1 * 10 ** TokenB.decimals());
        //set amount for borrower to borrow
        deal(
            address(TokenAAddress),
            address(cTokenA),
            10000 * 10 ** TokenA.decimals()
        );

        vm.startPrank(user1);
        TokenB.approve(address(cTokenB), 1 * 10 ** TokenB.decimals());
        cTokenB.mint(1 * 10 ** TokenB.decimals());
        assertEq(cTokenB.balanceOf(user1), 1 * 10 ** cTokenB.decimals());
        address[] memory ctokenAddress = new address[](1);
        ctokenAddress[0] = address(cTokenB);

        uint256[] memory err = unitroller.enterMarkets(ctokenAddress);
        (uint error, uint liquidity, uint shortfall) = unitroller
            .getAccountLiquidity(user1);
        // console.log("liquidity: %s", liquidity);
        // console.log("shortfall: %s", shortfall);

        cTokenA.borrow(50 * 10 ** cTokenA.decimals());
        vm.stopPrank();
    }

    function test_mint_and_redeem() public {
        initialCErc20Balance = 100;
        deal(
            address(TokenAAddress),
            user1,
            initialCErc20Balance * 10 ** TokenA.decimals()
        );
        vm.startPrank(user1);
        TokenA.approve(
            address(cTokenA),
            initialCErc20Balance * 10 ** TokenA.decimals()
        );
        cTokenA.mint(initialCErc20Balance * 10 ** TokenA.decimals());
        assertEq(
            cTokenA.balanceOf(user1),
            initialCErc20Balance * 10 ** cTokenA.decimals()
        );
        cTokenA.redeem(initialCErc20Balance * 10 ** TokenA.decimals());
        assertEq(cTokenA.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_borrow() public {
        user1_borrow_tokenA();
        assertEq(TokenA.balanceOf(user1), 50 * 10 ** cTokenA.decimals());
        vm.stopPrank();
    }

    function test_borrow_and_collateral_factor_liquidate() public {
        user1_borrow_tokenA();

        deal(address(TokenAAddress), user2, 1 * 25 ** TokenA.decimals());
        vm.prank(adminAddress);
        unitroller._setCollateralFactor(CToken(address(cTokenB)), 3e17);

        (uint error1, uint liquidity1, uint shortfall1) = unitroller
            .getAccountLiquidity(user1);
        assertEq(shortfall1 > 0, true);

        vm.startPrank(user2);
        TokenA.approve(address(cTokenA), 25 * 10 ** TokenA.decimals());
        cTokenA.liquidateBorrow(
            user1,
            25 * 10 ** cTokenA.decimals(),
            CTokenInterface(address(cTokenB))
        );

        (uint error2, uint liquidity2, uint shortfall2) = unitroller
            .getAccountLiquidity(user1);
        assertEq(liquidity2 > 0, true);

        vm.stopPrank();
    }

    function test_borrow_and_oracle_liquidate() public {
        user1_borrow_tokenA();

        deal(address(TokenAAddress), user2, 1 * 25 ** TokenA.decimals());

        vm.prank(adminAddress);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 70 * 1e18);

        (uint error1, uint liquidity1, uint shortfall1) = unitroller
            .getAccountLiquidity(user1);
        // console.log("liquidity1: %s", liquidity1);
        // console.log("shortfall1: %s", shortfall1);
        assertEq(shortfall1 > 0, true);

        vm.startPrank(user2);
        TokenA.approve(address(cTokenA), 25 * 10 ** TokenA.decimals());
        cTokenA.liquidateBorrow(
            user1,
            25 * 10 ** cTokenA.decimals(),
            CTokenInterface(address(cTokenB))
        );

        (uint error2, uint liquidity2, uint shortfall2) = unitroller
            .getAccountLiquidity(user1);
        // console.log("liquidity2: %s", liquidity2);
        // console.log("shortfall2: %s", shortfall2);
        assertEq(liquidity2 > 0, true);

        vm.stopPrank();
    }
}
