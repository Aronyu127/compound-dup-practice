pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/MyErc20.sol";
import "../contracts/SimplePriceOracle.sol";
import "../contracts/Comptroller.sol";
import "../contracts/ComptrollerInterface.sol";
import "../contracts/Unitroller.sol";
import "../contracts/CErc20Delegate.sol";
import "../contracts/CErc20Delegator.sol";
import "../contracts/WhitePaperInterestRateModel.sol";
import "../contracts/InterestRateModel.sol";

contract Deploy is Script {
    bool deployOnChain = vm.envBool("DEPLOY_ON_CHAIN");
    address TokenAAddress;
    address TokenBAddress;
    address adminAddress;
    address oracleAddress;
    address payable cTokenAAddress;
    address payable cTokenBAddress;
    address unitrollerAddress;
    function setUp() public virtual {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);
        adminAddress = makeAddr("admin");
        vm.startPrank(adminAddress);
        if (deployOnChain) {
          vm.startBroadcast(vm.envUint("MAINNET_PRIVATE_KEY"));
        }
        //create token
        MyErc20 token = new MyErc20("MyToken", "MTK");
        MyErc20 token2 = new MyErc20("MyToken2", "MTK2");
        //create price oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        oracleAddress = address(priceOracle);
        //create comptroller
        Comptroller comptroller = new Comptroller();
        
        //create unitroller and set comptroller as implementation
        Unitroller unitroller = new Unitroller();
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        Comptroller comptroller_warp_unitorller = Comptroller(address(unitroller));
        comptroller_warp_unitorller._setPriceOracle(priceOracle);
        unitrollerAddress = address(unitroller);
        //create interestrate model
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(
                0,
                0
            );

        //create CErc20Delegate
        CErc20Delegate cErc20Delegate = new CErc20Delegate();
        ComptrollerInterface comptrollerInterface = ComptrollerInterface(
            address(unitroller)
        );
        InterestRateModel interestRateModelInterface = InterestRateModel(
            address(interestRateModel)
        );
        address payable admin = payable(msg.sender);

        CErc20Delegator cTokenA = new CErc20Delegator(
            address(token),
            comptrollerInterface,
            interestRateModelInterface,
            1 * 1e18,
            "Compound MTK",
            "cMTK",
            18,
            admin,
            address(cErc20Delegate),
            ""
        );
        CErc20Delegator cTokenB = new CErc20Delegator(
            address(token2),
            comptrollerInterface,
            interestRateModelInterface,
            1 * 1e18,
            "Compound MTK2",
            "cMTK2",
            18,
            admin,
            address(cErc20Delegate),
            ""
        );
        priceOracle.setUnderlyingPrice(CToken(address(cTokenA)), 1 * 1e18);
        priceOracle.setUnderlyingPrice(CToken(address(cTokenB)), 100 * 1e18);
        comptroller_warp_unitorller._supportMarket(CToken(address(cTokenA)));
        comptroller_warp_unitorller._setCloseFactor(5e17);
        comptroller_warp_unitorller._supportMarket(CToken(address(cTokenB)));
        comptroller_warp_unitorller._setCollateralFactor(CToken(address(cTokenB)), 5e17);
        cTokenAAddress = payable(address(cTokenA));
        cTokenBAddress = payable(address(cTokenB));
        TokenAAddress = address(token);
        TokenBAddress = address(token2);
        if (deployOnChain) {
          vm.stopBroadcast();
        }

        vm.stopPrank();
    }

    function run() external {
}
}
