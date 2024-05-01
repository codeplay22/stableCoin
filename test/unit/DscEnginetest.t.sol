//SPDX-License-Identifier:MIT

import{Test} from "forge-std/Test.sol";
import{console} from "forge-std/console.sol";
import{DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol" ;
import{DSCEngine} from "../../src/DSCEngine.sol";
import{HelperConfig} from "../../script/HelperConfig.s.sol";
import{ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract DscEngineTest is Test{
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant Amount_Collateral = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    function setUp()  public {

        deployer = new DeployDSC();
        (dsc,dsce,config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);

    }

    ///////////////////////////
    ///Constructor Tests //////
    ///////////////////////////
    address[] public tokensAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthsDoesntMatchPriceFeeds() public {
        tokensAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokensAddresses, priceFeedAddresses, address(dsc));
    }
    
    /////////////////////
    ///Price Tests //////
    ////////////////////


    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        console.log("weth is",weth);

        // assertEq(expectedUsd, actualUsd);
        console.log("actualUsd is ",actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000 /ETH, $100
        uint256 expectedWeth = 0.033333333333333333 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        console.log("actualWeth is", actualWeth);
        console.log("expectedWeth is", expectedWeth);
        assertEq(expectedWeth,actualWeth);
    }

     ////////////////////////////////
    ///depositCollateral Test //////
    ////////////////////////////////


    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dsce),Amount_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();
    }


    function testRevertsWithUnapprovedCollateral() public{
        //RAN means Random token
        ERC20Mock ranToken = new ERC20Mock("RAN","RAN", USER, Amount_Collateral);
        vm.startPrank(USER);
        console.log("USER is",USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), Amount_Collateral);
        vm.stopPrank();
    }

    // modifier depositedCollateral() {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approveInternal(USER, address(dsce),Amount_Collateral);
    //     dsce.depositCollateral(weth, Amount_Collateral);
    //     vm.stopPrank();
    //     _;
    // }

    // function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{
        
    //     (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
    //     uint256 expectedTotalDscMinted = 0;
    //     console.log("collateralValueInUsd is",collateralValueInUsd);
    //     console.log("totalDscMinted is",totalDscMinted);
    //     uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);
    //     console.log("expectedCollateralValueInUsd is",expectedDepositAmount);
    //     assertEq(totalDscMinted, expectedTotalDscMinted);
    //     assertEq(Amount_Collateral, expectedDepositAmount);

    // }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approveInternal(USER, address(dsce),Amount_Collateral);
        dsce.depositCollateral(weth, Amount_Collateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral{
        
        (uint256 totalDscMinted,uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        console.log("USER IS inside test",USER);
        // console.log("collateralValueInUsd is",collateralValueInUsd);
        // console.log("totalDscMinted is",totalDscMinted);
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);
        // console.log("expectedCollateralValueInUsd is",expectedDepositAmount);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(Amount_Collateral, expectedDepositAmount);

    }





}