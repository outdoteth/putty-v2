// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestFees is Fixture {
    event FilledOrder(bytes32 indexed orderHash, uint256[] floorAssetTokenIds, PuttyV2.Order order);

    address[] internal whitelist;
    address[] internal floorTokens;
    PuttyV2.ERC20Asset[] internal erc20Assets;
    PuttyV2.ERC721Asset[] internal erc721Assets;
    uint256[] internal floorAssetTokenIds;

    receive() external payable {}

    function setUp() public {
        deal(address(weth), address(this), 0xffffffff);
        deal(address(weth), babe, 0xffffffff);

        deal(babe, 0xffffffff);
        deal(address(this), 0xffffffff);

        weth.approve(address(p), type(uint256).max);

        vm.prank(babe);
        weth.approve(address(p), type(uint256).max);
    }

    function testItCollectsFeesForLong() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        order.isLong = true;
        bytes memory signature = signOrder(babePrivateKey, order);
        uint256 fee = 25;
        p.setFee(fee);
        uint256 takerBalanceBefore = ERC20(order.baseAsset).balanceOf(address(this));

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);

        // assert
        uint256 expectedFee = (order.premium * fee) / 1000;
        assertEq(p.unclaimedFees(order.baseAsset), expectedFee, "Should have incremented unclaimed fees");
        assertEq(ERC20(order.baseAsset).balanceOf(address(p)), expectedFee, "Should have transferred fee to contract");
        assertEq(
            ERC20(order.baseAsset).balanceOf(address(this)) - takerBalanceBefore,
            order.premium - expectedFee,
            "Should have transferred baseAsset to taker"
        );
    }

    function testItCollectsFeesForShort() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        order.isLong = false;
        bytes memory signature = signOrder(babePrivateKey, order);
        uint256 fee = 25;
        p.setFee(fee);
        uint256 makerBalanceBefore = ERC20(order.baseAsset).balanceOf(order.maker);

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);

        // assert
        uint256 expectedFee = (order.premium * fee) / 1000;
        assertEq(p.unclaimedFees(order.baseAsset), expectedFee, "Should have incremented unclaimed fees");
        assertEq(ERC20(order.baseAsset).balanceOf(address(p)), expectedFee, "Should have transferred fee to contract");
        assertEq(
            ERC20(order.baseAsset).balanceOf(order.maker) - makerBalanceBefore,
            order.premium - expectedFee,
            "Should have transferred baseAsset to maker"
        );
    }

    function testItCollectsFeesForNativeETH() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        order.isLong = false;
        order.baseAsset = address(weth);
        bytes memory signature = signOrder(babePrivateKey, order);
        uint256 fee = 25;
        p.setFee(fee);
        uint256 makerBalanceBefore = weth.balanceOf(order.maker);

        // act
        p.fillOrder{value: order.premium}(order, signature, floorAssetTokenIds);

        // assert
        uint256 expectedFee = (order.premium * fee) / 1000;
        assertEq(weth.balanceOf(address(p)), expectedFee, "Should have transferred fee to contract");
        assertEq(p.unclaimedFees(order.baseAsset), expectedFee, "Should have incremented unclaimed fees");
        assertEq(
            weth.balanceOf(order.maker) - makerBalanceBefore,
            order.premium - expectedFee,
            "Should have transferred ETH to maker"
        );
    }

    function testItWithdrawsFees() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        order.isLong = false;
        order.baseAsset = address(weth);
        bytes memory signature = signOrder(babePrivateKey, order);
        uint256 fee = 25;
        p.setFee(fee);
        p.fillOrder{value: order.premium}(order, signature, floorAssetTokenIds);
        uint256 balanceBefore = ERC20(order.baseAsset).balanceOf(address(this));

        // act
        p.withdrawFees(order.baseAsset, address(this));

        // assert
        uint256 expectedFee = (order.premium * fee) / 1000;
        assertEq(p.unclaimedFees(order.baseAsset), 0, "Should have reset fees");
        assertEq(
            ERC20(order.baseAsset).balanceOf(address(this)) - balanceBefore,
            expectedFee,
            "Should have withdrawn fee"
        );
    }
}
