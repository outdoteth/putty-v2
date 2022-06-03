// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestExercise is Fixture {
    address[] internal whitelist;
    address[] internal floorTokens;
    PuttyV2.ERC20Asset[] internal erc20Assets;
    PuttyV2.ERC721Asset[] internal erc721Assets;
    uint256[] internal floorAssetTokenIds;

    receive() external payable {}

    function setUp() public {
        PuttyV2.Order memory order = defaultOrder();

        vm.deal(address(this), order.premium + order.strike);
        weth.deposit{value: order.premium + order.strike}();
        weth.approve(address(p), order.premium + order.strike);

        vm.startPrank(babe);
        vm.deal(babe, order.premium + order.strike);
        weth.deposit{value: order.premium + order.strike}();
        weth.approve(address(p), order.premium + order.strike);
        vm.stopPrank();
    }
}
