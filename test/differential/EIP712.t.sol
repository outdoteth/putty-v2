// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "src/PuttyV2.sol";
import "../shared/Fixture.t.sol";

contract TestEIP712 is Fixture {
    function testRecoveredSignerMatchesEthersEIP712Implementation() public {}

    function testOrderHashMatchesEthersEIP712Implementation(PuttyV2.Order memory order) public {
        // arrange
        string[] memory runJsInputs = new string[](3);
        runJsInputs[0] = "node";
        runJsInputs[1] = "./test/differential/scripts/hash-order-cli.js";
        runJsInputs[2] = toHexString(abi.encode(order));

        // act
        bytes memory ethersResult = vm.ffi(runJsInputs);
        bytes32 ethersGeneratedHash = abi.decode(ethersResult, (bytes32));
        bytes32 orderHash = ECDSA.toTypedDataHash(p.domainSeparatorV4(), p.hashOrder(order));

        // assert
        assertEq(orderHash, ethersGeneratedHash, "Should have generated same hash");
    }

    function toHexString(bytes memory input) public pure returns (string memory) {
        require(input.length < type(uint256).max / 2 - 1, "Invalid input");
        bytes16 symbols = "0123456789abcdef";
        bytes memory hexBuffer = new bytes(2 * input.length + 2);
        hexBuffer[0] = "0";
        hexBuffer[1] = "x";

        uint256 pos = 2;
        uint256 length = input.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 _byte = uint8(input[i]);
            hexBuffer[pos++] = symbols[_byte >> 4];
            hexBuffer[pos++] = symbols[_byte & 0xf];
        }

        return string(hexBuffer);
    }
}
