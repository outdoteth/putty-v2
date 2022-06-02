// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestEIP712 is Fixture {
    address[] internal whitelist;
    address[] internal floorTokens;
    PuttyV2.ERC20Asset[] internal erc20Assets;
    PuttyV2.ERC721Asset[] internal erc721Assets;
    uint256[] internal floorAssetTokenIds;

    function setUp() public {}

    function testItCannotUseInvalidSignature() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        bytes memory signature;

        // act
        vm.expectRevert("Invalid signature");
        p.fillOrder(order, signature, floorAssetTokenIds);
    }

    function testItCannotFillOrderThatIsCancelled() public {
        // TODO: implement this when cancelorder is available
    }

    function testItCannotFillOrderIfNotWhitelisted() public {
        // arrange
        whitelist.push(bob);
        PuttyV2.Order memory order = defaultOrder();
        order.whitelist = whitelist;

        bytes memory signature = signOrder(babePrivateKey, order);

        // act
        vm.expectRevert("Not whitelisted");
        p.fillOrder(order, signature, floorAssetTokenIds);
    }

    function testItCannotFillOrderWithFloorAssetTokenIdsIfOrderIsNotLongCall() public {
        // arrange
        floorAssetTokenIds.push(0x1337);

        // act
        // long put option order
        PuttyV2.Order memory longPutOrder = defaultOrder();
        longPutOrder.isCall = false;
        longPutOrder.isLong = true;

        bytes memory longPutOrderSignature = signOrder(babePrivateKey, longPutOrder);

        vm.expectRevert("Invalid floor tokens length");
        p.fillOrder(longPutOrder, longPutOrderSignature, floorAssetTokenIds);

        // short put option order
        PuttyV2.Order memory shortPutOrder = longPutOrder;
        shortPutOrder.isCall = false;
        shortPutOrder.isLong = false;
        bytes memory shortPutOrderSignature = signOrder(babePrivateKey, shortPutOrder);

        vm.expectRevert("Invalid floor tokens length");
        p.fillOrder(shortPutOrder, shortPutOrderSignature, floorAssetTokenIds);

        // short call option order
        PuttyV2.Order memory shortCallOrder = longPutOrder;
        shortCallOrder.isCall = true;
        shortCallOrder.isLong = false;
        bytes memory shortCallOrderSignature = signOrder(babePrivateKey, shortCallOrder);

        vm.expectRevert("Invalid floor tokens length");
        p.fillOrder(shortCallOrder, shortCallOrderSignature, floorAssetTokenIds);
    }

    function testItCannotSendIncorrectAmountOfFloorTokenIds() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        floorAssetTokenIds.push(0x1337);
        floorAssetTokenIds.push(0x1337);
        floorTokens.push(bob);
        order.floorTokens = floorTokens;

        bytes memory signature = signOrder(babePrivateKey, order);

        // act
        vm.expectRevert("Wrong amount of floor tokenIds");
        p.fillOrder(order, signature, floorAssetTokenIds);
    }

    function testItMintsPositionToMaker() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        bytes memory signature = signOrder(babePrivateKey, order);
        bytes32 orderHash = p.hashOrder(order);

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);

        // assert
        assertEq(p.ownerOf(uint256(orderHash)), order.maker, "Should have minted position to maker");
    }

    function testItMintsOppositePositionToTaker() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        bytes memory signature = signOrder(babePrivateKey, order);

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);
        order.isLong = !order.isLong;
        bytes32 oppositeOrderHash = p.hashOrder(order);

        // assert
        assertEq(p.ownerOf(uint256(oppositeOrderHash)), address(this), "Should have minted opposite position to taker");
    }

    function testItSavesFloorAssetTokenIds() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        floorTokens.push(bob);
        floorTokens.push(bob);

        order.floorTokens = floorTokens;
        floorAssetTokenIds.push(0x1337);
        floorAssetTokenIds.push(0x133);

        bytes memory signature = signOrder(babePrivateKey, order);
        bytes32 orderHash = p.hashOrder(order);

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);

        // assert
        assertEq(
            p.positionFloorAssetTokenIds(uint256(orderHash), 0),
            floorAssetTokenIds[0],
            "Should have saved floor asset token ids"
        );

        assertEq(
            p.positionFloorAssetTokenIds(uint256(orderHash), 1),
            floorAssetTokenIds[1],
            "Should have saved floor asset token ids"
        );
    }

    function testItSetsExpiration() public {
        // arrange
        PuttyV2.Order memory order = defaultOrder();
        bytes memory signature = signOrder(babePrivateKey, order);
        bytes32 orderHash = p.hashOrder(order);
        uint256 expectedExpiration = block.timestamp + order.duration;

        // act
        p.fillOrder(order, signature, floorAssetTokenIds);

        // assert
        assertEq(
            p.positionExpirations(uint256(orderHash)),
            expectedExpiration,
            "Should have set expiration to block.timestamp + duration"
        );
    }

    function testItSendsPremiumToMakerIfShort() public {}

    function testItSendsPremiumToTakerIfLong() public {}
}
