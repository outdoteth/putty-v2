// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestCancel is Fixture {
    address[] internal whitelist;
    address[] internal floorTokens;
    PuttyV2.ERC20Asset[] internal erc20Assets;
    PuttyV2.ERC721Asset[] internal erc721Assets;
    uint256[] internal floorAssetTokenIds;

    receive() external payable {}

    function setUp() public {
        deal(address(weth), address(this), 0xffffffff);
        deal(address(weth), babe, 0xffffffff);

        weth.approve(address(p), type(uint256).max);

        vm.prank(babe);
        weth.approve(address(p), type(uint256).max);
    }

    function testItCannotCancelOrderYouDontOwn() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();

        // act
        vm.expectRevert("Not your order");
        p.cancel(order);
    }

    function testItSetsOrderAsCancelled() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();

        // act
        vm.prank(babe);
        p.cancel(order);

        // assert
        assertEq(p.cancelledOrders(p.hashOrder(order)), true, "Should have marked order as cancelled");
    }
}
