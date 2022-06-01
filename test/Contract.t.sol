// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./shared/Fixture.t.sol";

contract TestContract is Fixture {
    function setUp() public {}

    function testBar() public {
        assertEq(uint256(1), uint256(1), "ok");
    }

    function testFoo(uint256 x) public {
        vm.assume(x < type(uint128).max);
        assertEq(x + x, x * 2);
    }
}
