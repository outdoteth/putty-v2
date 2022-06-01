// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PuttyV2 {
    enum OptionType {
        Call,
        Put
    }

    enum Side {
        Long,
        Short
    }

    struct ERC721Asset {
        address token;
        uint256 tokenId;
    }

    struct ERC20Asset {
        address token;
        uint256 tokenAmount;
    }

    struct Order {
        address maker;
        OptionType optionType;
        Side side;
        address baseAsset;
        uint256 strike;
        uint256 premium;
        uint256 duration;
        uint256 expiration;
        address[] whitelist;
        uint256 nonce;
        address[] floorAssets;
        ERC20Asset[] erc20Assets;
        ERC721Asset[] erc721Assets;
    }

    function fillOrder(
        Order calldata order,
        bytes32 signature,
        uint256[] calldata floorAssetTokenIds
    ) public {}
}
