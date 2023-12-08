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
    CErc20Delegator public cErc20Delegator;
    CErc20Delegator public cErc20Delegator2;
    // ComptrollerInterface public unitroller;
    Comptroller public unitroller;
    SimplePriceOracle public priceOracle;
    MyErc20 public myToken;
    MyErc20 public myToken2;

    function setUp() public override {
        super.setUp();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        cErc20Delegator = CErc20Delegator(cErc20DelegatorAddress);
        cErc20Delegator2 = CErc20Delegator(cErc20Delegator2Address);
        priceOracle = SimplePriceOracle(oracleAddress);
        unitroller = Comptroller(unitrollerAddress);
        myToken = MyErc20(MyTokenAddress);
        myToken2 = MyErc20(MyToken2Address);
        
    }

    function test_mint_and_redeem() public {
        initialCErc20Balance = 100;
        deal(address(MyTokenAddress), user1, initialCErc20Balance * 10 ** myToken.decimals());
        vm.startPrank(user1);
        myToken.approve(address(cErc20Delegator), initialCErc20Balance * 10 ** myToken.decimals());
        cErc20Delegator.mint(initialCErc20Balance * 10 ** myToken.decimals());
        assertEq(cErc20Delegator.balanceOf(user1), initialCErc20Balance * 10 ** cErc20Delegator.decimals());
        cErc20Delegator.redeem(initialCErc20Balance * 10 ** myToken.decimals());
        assertEq(cErc20Delegator.balanceOf(user1), 0);
        vm.stopPrank();
    }

    function test_borrow() public {
      deal(address(MyToken2Address), user1, 1 * 10 ** myToken2.decimals());      
      //set amount for borrower to borrow
      deal(address(MyTokenAddress), address(cErc20Delegator), 10000 * 10 ** myToken.decimals());
      
      vm.startPrank(user1);
      myToken2.approve(address(cErc20Delegator2), 1 * 10 ** myToken2.decimals());
      cErc20Delegator2.mint(1 * 10 ** myToken2.decimals());
      assertEq(cErc20Delegator2.balanceOf(user1), 1 * 10 ** cErc20Delegator2.decimals());
      address[] memory ctokenAddress = new address[](1);
      ctokenAddress[0] = address(cErc20Delegator2);


      uint256 [] memory err = unitroller.enterMarkets(ctokenAddress);
      (uint error, uint liquidity, uint shortfall) = unitroller.getAccountLiquidity(user1);
      // console.log("liquidity: %s", liquidity);
      // console.log("shortfall: %s", shortfall);
      
      cErc20Delegator.borrow(50 * 10 ** cErc20Delegator.decimals());
      assertEq(myToken.balanceOf(user1), 50 * 10 ** cErc20Delegator.decimals());
      vm.stopPrank();
    }

    function test_borrow_and_collateral_factor_liquidate() public {
      deal(address(MyToken2Address), user1, 1 * 10 ** myToken2.decimals());
      deal(address(MyTokenAddress), user2, 1 * 25 ** myToken.decimals());
      //set amount for borrower to borrow
      deal(address(MyTokenAddress), address(cErc20Delegator), 10000 * 10 ** myToken.decimals());
      vm.startPrank(user1);
      myToken2.approve(address(cErc20Delegator2), 1 * 10 ** myToken2.decimals());
      cErc20Delegator2.mint(1 * 10 ** myToken2.decimals());
      address[] memory ctokenAddress = new address[](1);
      ctokenAddress[0] = address(cErc20Delegator2);
      uint256 [] memory err = unitroller.enterMarkets(ctokenAddress);
      (uint error, uint liquidity, uint shortfall) = unitroller.getAccountLiquidity(user1);
      cErc20Delegator.borrow(50 * 10 ** cErc20Delegator.decimals());
      assertEq(liquidity > 0, true);

      vm.stopPrank();

      vm.prank(adminAddress);
      unitroller._setCollateralFactor(CToken(address(cErc20Delegator2)), 3e17);

      (uint error1, uint liquidity1, uint shortfall1) = unitroller.getAccountLiquidity(user1);
      assertEq(shortfall1 > 0, true);

      vm.startPrank(user2);
      myToken.approve(address(cErc20Delegator), 25 * 10 ** myToken.decimals());
      cErc20Delegator.liquidateBorrow(user1, 25 * 10 ** cErc20Delegator.decimals(), CTokenInterface(address(cErc20Delegator2)));

      (uint error2, uint liquidity2, uint shortfall2) = unitroller.getAccountLiquidity(user1);
      assertEq(liquidity2 > 0, true);

      vm.stopPrank();
    }

    function test_borrow_and_oracle_liquidate() public {
      deal(address(MyToken2Address), user1, 1 * 10 ** myToken2.decimals());
      deal(address(MyTokenAddress), user2, 1 * 25 ** myToken.decimals());
      //set amount for borrower to borrow
      deal(address(MyTokenAddress), address(cErc20Delegator), 10000 * 10 ** myToken.decimals());
      vm.startPrank(user1);
      myToken2.approve(address(cErc20Delegator2), 1 * 10 ** myToken2.decimals());
      cErc20Delegator2.mint(1 * 10 ** myToken2.decimals());
      address[] memory ctokenAddress = new address[](1);
      ctokenAddress[0] = address(cErc20Delegator2);
      uint256 [] memory err = unitroller.enterMarkets(ctokenAddress);
      (uint error, uint liquidity, uint shortfall) = unitroller.getAccountLiquidity(user1);
      // console.log("liquidity: %s", liquidity);
      // console.log("shortfall: %s", shortfall);
      cErc20Delegator.borrow(50 * 10 ** cErc20Delegator.decimals());
      assertEq(liquidity > 0, true);

      vm.stopPrank();

      vm.prank(adminAddress);
      priceOracle.setUnderlyingPrice(CToken(address(cErc20Delegator2)), 70 * 1e18);

      (uint error1, uint liquidity1, uint shortfall1) = unitroller.getAccountLiquidity(user1);
      // console.log("liquidity1: %s", liquidity1);
      // console.log("shortfall1: %s", shortfall1);
      assertEq(shortfall1 > 0, true);

      vm.startPrank(user2);
      myToken.approve(address(cErc20Delegator), 25 * 10 ** myToken.decimals());
      cErc20Delegator.liquidateBorrow(user1, 25 * 10 ** cErc20Delegator.decimals(), CTokenInterface(address(cErc20Delegator2)));

      (uint error2, uint liquidity2, uint shortfall2) = unitroller.getAccountLiquidity(user1);
      // console.log("liquidity2: %s", liquidity2);
      // console.log("shortfall2: %s", shortfall2);
      assertEq(liquidity2 > 0, true);

      vm.stopPrank();
    }
}
