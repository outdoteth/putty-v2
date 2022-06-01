// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/PuttyV2.sol";
import "./shared/Fixture.t.sol";

contract TestContract is Fixture {
    function setUp() public {}

    address[] addressList;
    uint256[] numberList;

    function testBar() public {
        addressList.push(babe);
        addressList.push(babe);
        numberList.push(0x1337);

        PuttyV2.Order memory order = PuttyV2.Order({
            maker: babe,
            isCall: false,
            isLong: false,
            baseAsset: bob,
            strike: 1,
            premium: 2,
            duration: 3,
            expiration: 4,
            nonce: 5,
            whitelist: addressList,
            floorTokens: addressList,
            erc20Tokens: addressList,
            erc721Tokens: addressList,
            erc20Amounts: numberList,
            erc721Ids: numberList
        });

        p.hashOrder(order);
    }

    function testFoo(uint256 x) public {
        vm.assume(x < type(uint128).max);
        assertEq(x + x, x * 2);
    }
}
