// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/utils/cryptography/draft-EIP712.sol";

import "forge-std/console.sol";

contract PuttyV2 is EIP712 {
    struct Order {
        address maker;
        bool isCall;
        bool isLong;
        address baseAsset;
        uint256 strike;
        uint256 premium;
        uint256 duration;
        uint256 expiration;
        uint256 nonce;
        address[] whitelist;
        address[] floorTokens;
        address[] erc20Tokens;
        address[] erc721Tokens;
        uint256[] erc20Amounts;
        uint256[] erc721Ids;
    }

    bytes32 constant ORDER_TYPE_HASH =
        keccak256(
            abi.encodePacked(
                "Order(",
                "address maker",
                "bool isCall",
                "bool isLong",
                "address baseAsset",
                "uint256 strike",
                "uint256 premium",
                "uint256 duration",
                "uint256 expiration",
                "uint256 nonce",
                "address[] whitelist",
                "address[] floorTokens",
                "address[] erc20Tokens",
                "address[] erc721Tokens",
                "uint256[] erc20Amounts",
                "uint256[] erc721Ids",
                ")"
            )
        );

    mapping(bytes32 => bool) public cancelledOrders;

    constructor() EIP712("Putty", "2.0") {}

    function fillOrder(
        Order memory order,
        bytes calldata signature,
        uint256[] calldata floorAssetTokenIds
    ) public {
        bytes32 orderHash = hashOrder(order);

        // check signature is valid using EIP-712
        bytes32 messageDigest = _hashTypedDataV4(orderHash);
        require(SignatureChecker.isValidSignatureNow(order.maker, messageDigest, signature), "Invalid signature");

        // check order is not cancelled
        require(!cancelledOrders[orderHash], "Order has been cancelled");

        // check msg.sender is in the order whitelist
        require(isWhitelisted(order.whitelist, msg.sender), "Not whitelisted");

        // check floor asset token ids length is 0 unless type is call and side is long
        order.isCall && order.isLong
            ? require(floorAssetTokenIds.length == order.floorTokens.length, "Wrong amount of floor tokenIds")
            : require(floorAssetTokenIds.length == 0 && order.floorTokens.length == 0, "Invalid floor tokens");

        Order memory oppositeOrder = order;
        oppositeOrder.isLong = !order.isLong;
        bytes32 oppositeOrderHash = hashOrder(oppositeOrder);

        // create side position for maker

        // create opposite side position for taker
    }

    function isWhitelisted(address[] memory whitelist, address target) public pure returns (bool) {
        if (whitelist.length == 0) return true;

        for (uint256 i = 0; i < whitelist.length; i++) {
            if (target == whitelist[i]) return true;
        }

        return false;
    }

    // hash order based on EIP-712 encoding
    function hashOrder(Order memory order) public pure returns (bytes32 orderHash) {
        bytes memory arrayEncodings = abi.encode(
            keccak256(abi.encodePacked(order.whitelist)),
            keccak256(abi.encodePacked(order.floorTokens)),
            keccak256(abi.encodePacked(order.erc20Tokens)),
            keccak256(abi.encodePacked(order.erc721Tokens)),
            keccak256(abi.encodePacked(order.erc20Amounts)),
            keccak256(abi.encodePacked(order.erc721Ids))
        );

        orderHash = keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.maker,
                order.isCall,
                order.isLong,
                order.baseAsset,
                order.strike,
                order.premium,
                order.duration,
                order.expiration,
                order.nonce,
                arrayEncodings
            )
        );
    }

    function hashAddressArray(address[] calldata arr) public view {}

    function hashUint256Array(uint256[] calldata arr) public view {}
}
