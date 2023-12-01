
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
    function run() external {
      uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
      vm.selectFork(forkId);
      vm.startBroadcast(vm.envUint("MAINNET_PRIVATE_KEY"));
      

      //create token
      MyErc20 token = new MyErc20("MyToken", "MTK");

      //create price oracle
      SimplePriceOracle priceOracle = new SimplePriceOracle();

      //create comptroller
      Comptroller comptroller = new Comptroller();
      comptroller._setPriceOracle(priceOracle);

      //create unitroller and set comptroller as implementation
      Unitroller unitroller = new Unitroller();
      unitroller._setPendingImplementation(address(comptroller));
      unitroller._acceptImplementation();
      
      //create interestrate model
      WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(0, 0);

      //create CErc20Delegate
      CErc20Delegate cErc20Delegate = new CErc20Delegate();
      ComptrollerInterface comptrollerInterface = ComptrollerInterface(address(comptroller));
      InterestRateModel interestRateModelInterface = InterestRateModel(address(interestRateModel));
      address payable admin = payable(msg.sender);

      CErc20Delegator cErc20Delegator = new CErc20Delegator(address(token), comptrollerInterface, interestRateModelInterface, 1, "Compound MTK", "cMTK", 18, admin, address(cErc20Delegate), "");
      vm.stopBroadcast();
    }
}
