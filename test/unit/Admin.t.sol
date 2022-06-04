// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestAdmin is Fixture {
    function testItCannotSetBaseURIIfNotAdmin() public {
        // act
        vm.prank(babe);
        vm.expectRevert("Ownable: caller is not the owner");
        p.setBaseURI("https://test.org/");
    }

    function testItCannotSetFeeIfNotAdmin() public {
        // act
        vm.prank(babe);
        vm.expectRevert("Ownable: caller is not the owner");
        p.setFee(100);
    }

    function testItSetsBaseURI() public {
        // arrange
        string memory baseURI = "https://new-test.org/";

        // act
        p.setBaseURI(baseURI);

        // assert
        assertEq(p.baseURI(), baseURI, "Should have set baseURI");
    }

    function testItSetsFee() public {
        // arrange
        uint256 fee = 100;

        // act
        p.setFee(fee);

        // assert
        assertEq(p.fee(), fee, "Should have set fee");
    }

    function testItCannotSetFeeGreaterThan3Percent() public {
        // arrange
        uint256 fee = 301;

        // act
        vm.expectRevert("fee must be less than 3%");
        p.setFee(fee);
    }
}
