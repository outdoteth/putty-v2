// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "openzeppelin/utils/introspection/ERC165.sol";

import "./PuttyV2.sol";

interface IPuttyV2Handler {
    function onFillOrder(
        PuttyV2.Order memory order,
        address taker,
        uint256[] memory floorAssetTokenIds
    ) external;

    function onExercise(
        PuttyV2.Order memory order,
        address exerciser,
        uint256[] memory floorAssetTokenIds
    ) external;
}

contract PuttyV2Handler is ERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IPuttyV2Handler).interfaceId || super.supportsInterface(interfaceId);
    }

    function onFillOrder(
        PuttyV2.Order memory order,
        address taker,
        uint256[] memory floorAssetTokenIds
    ) public virtual {}

    function onExercise(
        PuttyV2.Order memory order,
        address exerciser,
        uint256[] memory floorAssetTokenIds
    ) public virtual {}
}
