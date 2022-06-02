// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/utils/cryptography/draft-EIP712.sol";
import "solmate/tokens/ERC721.sol";

import "forge-std/console.sol";

contract PuttyV2 is EIP712, ERC721 {
    struct ERC20Asset {
        address token;
        uint256 tokenAmount;
    }

    struct ERC721Asset {
        address token;
        uint256 tokenId;
    }

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
        ERC20Asset[] erc20Assets;
        ERC721Asset[] erc721Assets;
    }

    bytes32 public constant ERC721ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC721Asset(address token,uint256 tokenId)"));

    bytes32 public constant ERC20ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC20Asset(address token,uint256 tokenAmount)"));

    bytes32 public constant ORDER_TYPE_HASH =
        keccak256(
            abi.encodePacked(
                "Order(",
                "address maker,",
                "bool isCall,",
                "bool isLong,",
                "address baseAsset,",
                "uint256 strike,",
                "uint256 premium,",
                "uint256 duration,",
                "uint256 expiration,",
                "uint256 nonce,"
                "address[] whitelist,",
                "address[] floorTokens,",
                "ERC20Asset[] erc20Assets,",
                "ERC721Asset[] erc721Assets",
                ")",
                "ERC20Asset(address token,uint256 tokenAmount)",
                "ERC721Asset(address token,uint256 tokenId)"
            )
        );

    mapping(bytes32 => bool) public cancelledOrders;
    mapping(uint256 => uint256[]) public positionFloorAssetTokenIds;
    mapping(uint256 => uint256) public positionExpirations;

    constructor() EIP712("Putty", "2.0") ERC721("Putty", "OPUT") {}

    function fillOrder(
        Order memory order,
        bytes calldata signature,
        uint256[] calldata floorAssetTokenIds
    ) public {
        /*
            ~~~ CHECKS ~~~
        */

        bytes32 orderHash = hashOrder(order);

        // check signature is valid using EIP-712
        require(SignatureChecker.isValidSignatureNow(order.maker, orderHash, signature), "Invalid signature");

        // check order is not cancelled
        require(!cancelledOrders[orderHash], "Order has been cancelled");

        // check msg.sender is allowed to fill the order
        require(order.whitelist.length == 0 || isWhitelisted(order.whitelist, msg.sender), "Not whitelisted");

        // check floor asset token ids length is 0 unless the order `type` is call and `side` is long
        order.isCall && order.isLong
            ? require(floorAssetTokenIds.length == order.floorTokens.length, "Wrong amount of floor tokenIds")
            : require(floorAssetTokenIds.length == 0 && order.floorTokens.length == 0, "Invalid floor tokens");

        /*
            ~~~ EFFECTS ~~~
        */

        // create side position for maker
        _mint(order.maker, uint256(orderHash));

        // create opposite side position for taker
        Order memory oppositeOrder = order;
        oppositeOrder.isLong = !order.isLong;
        bytes32 oppositeOrderHash = hashOrder(oppositeOrder);
        _mint(msg.sender, uint256(oppositeOrderHash));

        // save floorAssetTokenIds
        positionFloorAssetTokenIds[uint256(orderHash)] = floorAssetTokenIds;

        // save the position expiration
        positionExpirations[uint256(orderHash)] = block.timestamp + order.duration;

        /*
            ~~~ INTERACTIONS ~~~
        */

        // filling short put
        if (!order.isLong && !order.isCall) {
            return;
        }

        // filling short call
        if (!order.isLong && order.isCall) {
            return;
        }

        // filling long put
        if (order.isLong && !order.isCall) {
            return;
        }

        // filling long call
        if (order.isLong && order.isCall) {
            return;
        }
    }

    function isWhitelisted(address[] memory whitelist, address target) public pure returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (target == whitelist[i]) return true;
        }

        return false;
    }

    // hash order based on EIP-712 encoding
    function hashOrder(Order memory order) public view returns (bytes32 orderHash) {
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
                keccak256(abi.encodePacked(order.whitelist)),
                keccak256(abi.encodePacked(order.floorTokens)),
                keccak256(encodeERC20Assets(order.erc20Assets)),
                keccak256(encodeERC721Assets(order.erc721Assets))
            )
        );

        orderHash = _hashTypedDataV4(orderHash);
    }

    function encodeERC721Assets(ERC721Asset[] memory arr) public pure returns (bytes memory encoded) {
        for (uint256 i = 0; i < arr.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                keccak256(abi.encode(ERC721ASSET_TYPE_HASH, arr[i].token, arr[i].tokenId))
            );
        }
    }

    function encodeERC20Assets(ERC20Asset[] memory arr) public pure returns (bytes memory encoded) {
        for (uint256 i = 0; i < arr.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                keccak256(abi.encode(ERC20ASSET_TYPE_HASH, arr[i].token, arr[i].tokenAmount))
            );
        }
    }

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return "";
    }

    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
