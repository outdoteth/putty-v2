// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "openzeppelin/interfaces/IERC1271.sol";
import "openzeppelin/utils/introspection/ERC165.sol";

import "../../src/PuttyV2Handler.sol";
import "../../src/PuttyV2.sol";

contract MockPuttyV2Handler is PuttyV2Handler, ERC165 {
    address public fillOrderTaker;
    address public exerciseTaker;

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        return IERC1271.isValidSignature.selector;
    }

    function onFillOrder(
        PuttyV2.Order memory order,
        address taker,
        uint256[] memory floorAssetTokenIds
    ) public override {
        fillOrderTaker = taker;

        // cause on OOG error if taker is 0xb0b
        if (taker == address(0xb0b)) {
            for (uint256 i = 100; i < 10_000; i++) {
                fillOrderTaker = address(0xb0b);
            }
        }
    }

    function onExercise(
        PuttyV2.Order memory order,
        address exerciser,
        uint256[] memory floorAssetTokenIds
    ) public override {
        exerciseTaker = exerciser;

        // cause on OOG error if exerciser is 0xb0b
        if (exerciser == address(0xb0b)) {
            for (uint256 i = 100; i < 10_000; i++) {
                fillOrderTaker = address(0xb0b);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IPuttyV2Handler).interfaceId || super.supportsInterface(interfaceId);
    }
}
