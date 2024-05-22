//Have Our invariant aka properties

//What are your invariants?

// 1. The Total supply of DSC(debt for us who owns the company) should be less than the total
// value of collateral.
// 2. Getter view functions should never revert <- evergreen variant

// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

// import{console} from "forge-std/console.sol";
import {Test,console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import{DeployDSC} from "../../script/DeployDSC.s.sol";
import{DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import{HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import{Handler} from "../fuzz/Handler.t.sol";

contract Invariants is StdInvariant, Test {
  
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
         (,,weth,wbtc,)= config.activeNetworkConfig();
        // targetContract(address(dsce));
        // Don't call redeem callateral, unless there's collateral to redeem
        handler = new Handler(dsce,dsc);
        targetContract(address(handler));

      }

      function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
        // get the value of all the collateral in the protocol
        // comapare it to all the debt(dsc)

        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        // console.log("totalBtcDeposited is",totalBtcDeposited);
        // console.log("totalWethDeposited is",totalWethDeposited);
        console.log("Times mint called:", handler.timesMintIsCalled());

        uint256 wethValue = dsce.getUsdValue(weth,totalWethDeposited);
        console.log("wethValue",wethValue);
        uint256 wbtcValue = dsce.getUsdValue(wbtc,totalBtcDeposited);
        console.log("wbtcValue",wbtcValue);
        console.log("total supply",totalSupply);
        assert(wethValue + wbtcValue >= totalSupply);

      }

}

