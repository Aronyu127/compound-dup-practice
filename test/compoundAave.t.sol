// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/Comptroller.sol";
import "../contracts/ComptrollerInterface.sol";
import "../contracts/Unitroller.sol";
import "../contracts/CErc20Delegate.sol";
import "../contracts/CErc20Delegator.sol";
import "../contracts/WhitePaperInterestRateModel.sol";
import "../contracts/InterestRateModel.sol";
import { FlashLoanLiquidate } from "../contracts/FlashLoanLiquidate.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CompoundAaveTest is Test {
    ERC20 public USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public UNI = ERC20(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
    address public user1;
    address public user2;
    CErc20Delegator public cUSDC;
    CErc20Delegator public cUNI;
    address payable public cUSDCAddress;
    address payable public cUNIAddress;
    Comptroller public unitroller;
    address public unitrollerAddress;
    SimplePriceOracle public priceOracle;
    Comptroller public comptrollerProxy;
    address adminAddress;
    address oracleAddress;
    address interestRateModelAddress;

    function setUp() public virtual {
        uint256 forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        uint256 blockNumber = 17465000;
        vm.rollFork(forkId, blockNumber);
        adminAddress = makeAddr("admin");
        vm.startPrank(adminAddress);
        //create price oracle
        priceOracle = new SimplePriceOracle();
        oracleAddress = address(priceOracle);
        //create comptroller
        Comptroller comptroller = new Comptroller();

        //create unitroller and set comptroller as implementation
        Unitroller unitroller = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        comptrollerProxy = Comptroller(address(unitroller));
        unitrollerAddress = address(unitroller);
        comptrollerProxy._setPriceOracle(priceOracle);
        //create interestrate model
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(0, 0);
        interestRateModelAddress = address(interestRateModel);

        //create CErc20Delegate
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        ComptrollerInterface comptrollerInterface = ComptrollerInterface(address(unitroller));
        InterestRateModel interestRateModelInterface = InterestRateModel(address(interestRateModel));
        CErc20Delegator cUSDCDelegator = new CErc20Delegator(
            address(USDC),
            comptrollerInterface,
            InterestRateModel(interestRateModelAddress),
            1 * 1e18,
            "Compound USDC",
            "cUSDC",
            18,
            payable(adminAddress),
            address(cErc20Delegate),
            ""
        );
        cUSDCAddress = payable(address(cUSDCDelegator));
        cUSDC = CErc20Delegator(cUSDCAddress); // TODO: 搞懂這個 不使用 payable 的話會過不了
        CErc20Delegator cUNIDelegator = new CErc20Delegator(
            address(UNI),
            comptrollerInterface,
            InterestRateModel(interestRateModelAddress),
            1 * 1e18,
            "Compound UNI",
            "cUNI",
            18,
            payable(adminAddress),
            address(cErc20Delegate),
            ""
        );
        cUNIAddress = payable(address(cUNIDelegator));
        cUNI = CErc20Delegator(cUNIAddress);
        priceOracle.setUnderlyingPrice(CToken(address(cUSDC)), 1 * 1e30);
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 5 * 1e18);
        comptrollerProxy._supportMarket(CToken(address(cUSDC)));
        comptrollerProxy._supportMarket(CToken(address(cUNI)));
        comptrollerProxy._setLiquidationIncentive(108 * 1e16);
        comptrollerProxy._setCollateralFactor(CToken(address(cUNI)), 5e17);
        comptrollerProxy._setCloseFactor(5e17);
        vm.stopPrank();
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
    }

    function test_borrow_and_aave_flash_loan_liquidate() public {
        vm.startPrank(user1);
        deal(address(UNI), user1, 1000 * 10 ** UNI.decimals());
        deal(address(USDC), address(cUSDC), 1000000 * 10 ** USDC.decimals());

        UNI.approve(cUNIAddress, 1000 * 10 ** UNI.decimals()); //TODO: 搞懂 decimals
        cUNI.mint(1000 * 10 ** UNI.decimals());
        address[] memory ctokenAddress = new address[](1);
        ctokenAddress[0] = address(cUNI);
        uint256[] memory err = comptrollerProxy.enterMarkets(ctokenAddress);
        print_address_liquidity(user1);
        cUSDC.borrow(2500 * 10 ** USDC.decimals());
        print_address_liquidity(user1);
        assertEq(USDC.balanceOf(user1), 2500 * 10 ** USDC.decimals());
        vm.stopPrank();

        vm.startPrank(adminAddress);
        priceOracle.setUnderlyingPrice(CToken(address(cUNI)), 4 * 10 ** UNI.decimals());
        vm.stopPrank();
        print_address_liquidity(user1);
        vm.startPrank(user2);
        FlashLoanLiquidate aaveFlashLoan = new FlashLoanLiquidate();
        aaveFlashLoan.requestFlashLoan(address(USDC), 1250 * 10 ** USDC.decimals(), abi.encode(cUSDC, cUNI, user1));
        aaveFlashLoan.withdraw(address(USDC));
        print_address_liquidity(user1);
        uint256 user2Usdc = USDC.balanceOf(user2);
        console.log("user2Usdc: %s", user2Usdc);
        assert(user2Usdc > 63 * 10 ** USDC.decimals());
        vm.stopPrank();   
    }

    function print_address_liquidity(address user) public {
        (uint256 error, uint256 liquidity, uint256 shortfall) = comptrollerProxy.getAccountLiquidity(user1);
        console.log("liquidity: %s", liquidity);
        console.log("shortfall: %s", shortfall);
    }

}
