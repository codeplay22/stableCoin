// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title Oracle
 * @author Anshuman Khaneja
 * @notice This library is used to check the chainlink oracle for stale data.
 * If the price is stale,the function will revert, and render the DSCEngine usable-this is by design.
 * We want the DSCEngine to freeze if prices become stale.
 * 
 * So if the chainlink network explodes and you have a lot of money in the protocol...
 */



library Oraclelib {

    error Oraclelib__StalePrice();
    

    uint256 private constant TIME_OUT = 3 hours; // 3 * 60 * 60 = 10800 seconds
    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed) public view  returns (uint80,int256,uint256,uint256,uint80) {
     (
      uint80 roundId,int256 answer,  uint256 startedAt,uint256 updatedAt,uint80 answeredInRound
    ) = priceFeed.latestRoundData();

    uint256 secondsSince = block.timestamp - updatedAt;
    if (secondsSince > TIME_OUT) {
        revert Oraclelib__StalePrice();
    }
    return (roundId,answer,startedAt,updatedAt,answeredInRound);

    }
}