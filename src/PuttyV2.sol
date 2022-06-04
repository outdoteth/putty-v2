// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/utils/cryptography/draft-EIP712.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC721.sol";

import "forge-std/console.sol";

contract PuttyV2 is EIP712, ERC721, ERC721TokenReceiver {
    using SafeTransferLib for ERC20;

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
    mapping(uint256 => bool) public exercisedPositions;

    constructor() EIP712("Putty", "2.0") ERC721("Putty", "OPUT") {}

    function fillOrder(
        Order memory order,
        bytes calldata signature,
        uint256[] calldata floorAssetTokenIds
    ) public returns (uint256 positionId) {
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

        // check duration is valid
        require(order.duration < 10_000 days, "Duration too long");

        // check order has not expired
        require(block.timestamp < order.expiration, "Order has expired");

        // check floor asset token ids length is 0 unless the order `type` is call and `side` is long
        order.isCall && order.isLong
            ? require(floorAssetTokenIds.length == order.floorTokens.length, "Wrong amount of floor tokenIds")
            : require(floorAssetTokenIds.length == 0, "Invalid floor tokens length");

        /*
            ~~~ EFFECTS ~~~
        */

        // create side position for maker
        _mint(order.maker, uint256(orderHash));

        // create opposite side position for taker
        Order memory oppositeOrder = abi.decode(abi.encode(order), (Order)); // decode/encode to get a copy instead of reference
        oppositeOrder.isLong = !order.isLong;
        positionId = uint256(hashOrder(oppositeOrder));
        _mint(msg.sender, positionId);

        // save floorAssetTokenIds
        positionFloorAssetTokenIds[uint256(orderHash)] = floorAssetTokenIds;

        // save the long position expiration
        positionExpirations[order.isLong ? uint256(orderHash) : positionId] = block.timestamp + order.duration;

        /*
            ~~~ INTERACTIONS ~~~
        */

        // transfer premium to whoever is short from whomever is long
        order.isLong
            ? ERC20(order.baseAsset).safeTransferFrom(order.maker, msg.sender, order.premium)
            : ERC20(order.baseAsset).safeTransferFrom(msg.sender, order.maker, order.premium);

        // filling short put
        // transfer strike from maker to contract
        if (!order.isLong && !order.isCall) {
            ERC20(order.baseAsset).safeTransferFrom(order.maker, address(this), order.strike);
        }

        // filling long put
        // transfer strike from taker to contract
        if (order.isLong && !order.isCall) {
            ERC20(order.baseAsset).safeTransferFrom(msg.sender, address(this), order.strike);
        }

        // filling short call
        // transfer assets from maker to contract
        if (!order.isLong && order.isCall) {
            _transferERC20sIn(order.erc20Assets, order.maker);
            _transferERC721sIn(order.erc721Assets, order.maker);
        }

        // filling long call
        // transfer assets from taker to contract
        if (order.isLong && order.isCall) {
            _transferERC20sIn(order.erc20Assets, msg.sender);
            _transferERC721sIn(order.erc721Assets, msg.sender);
            _transferFloorsIn(order.floorTokens, floorAssetTokenIds, msg.sender);
        }
    }

    function exercise(Order memory order, uint256[] calldata floorAssetTokenIds) public {
        /*
            ~~~ CHECKS ~~~
        */

        bytes32 orderHash = hashOrder(order);

        // check user owns the position
        require(ownerOf(uint256(orderHash)) == msg.sender, "Not owner");

        // check position is long
        require(order.isLong, "Can only exercise long positions");

        // check position has not expired
        require(block.timestamp < positionExpirations[uint256(orderHash)], "Position has expired");

        // check floor asset token ids length is 0 unless the position `type` is put
        !order.isCall
            ? require(floorAssetTokenIds.length == order.floorTokens.length, "Wrong amount of floor tokenIds")
            : require(floorAssetTokenIds.length == 0, "Invalid floor tokenIds length");

        /*
            ~~~ EFFECTS ~~~
        */

        // send the long position to 0xdead.
        // instead of doing a standard burn by sending to 0x000...000, sending
        // to 0xdead ensures that the same position id cannot be minted again.
        transferFrom(msg.sender, address(0xdead), uint256(orderHash));

        // mark the position as exercised
        exercisedPositions[uint256(orderHash)] = true;

        // save the floor asset token ids
        Order memory oppositeOrder = abi.decode(abi.encode(order), (Order)); // decode/encode to get a copy instead of reference
        oppositeOrder.isLong = false;
        uint256 shortPositionId = uint256(hashOrder(oppositeOrder));
        positionFloorAssetTokenIds[shortPositionId] = floorAssetTokenIds;

        /*
            ~~~ INTERACTIONS ~~~
        */

        if (order.isCall) {
            // -- exercising a call option

            // transfer strike from exerciser to putty
            ERC20(order.baseAsset).safeTransferFrom(msg.sender, address(this), order.strike);

            // transfer erc20 assets to exerciser
            for (uint256 i = 0; i < order.erc20Assets.length; i++) {
                ERC20(order.erc20Assets[i].token).safeTransfer(msg.sender, order.erc20Assets[i].tokenAmount);
            }

            // transfer erc721 assets to exerciser
            for (uint256 i = 0; i < order.erc721Assets.length; i++) {
                ERC721(order.erc721Assets[i].token).safeTransferFrom(
                    address(this),
                    msg.sender,
                    order.erc721Assets[i].tokenId
                );
            }

            // transfer erc721 floor assets to exerciser
            uint256[] memory callFloorAssetTokenIds = positionFloorAssetTokenIds[uint256(orderHash)];
            for (uint256 i = 0; i < order.floorTokens.length; i++) {
                ERC721(order.floorTokens[i]).safeTransferFrom(address(this), msg.sender, callFloorAssetTokenIds[i]);
            }
        } else {
            // -- exercising a put option

            // transfer strike from putty to exerciser
            ERC20(order.baseAsset).safeTransfer(msg.sender, order.strike);

            // transfer assets from exerciser to putty
            _transferERC20sIn(order.erc20Assets, msg.sender);
            _transferERC721sIn(order.erc721Assets, msg.sender);
            _transferFloorsIn(order.floorTokens, floorAssetTokenIds, msg.sender);
        }
    }

    function withdraw(Order memory order) public {
        /*
            ~~~ CHECKS ~~~
        */

        // check order is short
        require(!order.isLong, "Can only withdraw short positions");

        bytes32 orderHash = hashOrder(order);

        // check msg.sender owns the position
        require(ownerOf(uint256(orderHash)) == msg.sender, "Not owner");

        Order memory oppositeOrder = abi.decode(abi.encode(order), (Order)); // decode/encode to get a copy instead of reference
        oppositeOrder.isLong = true;
        uint256 longPositionId = uint256(hashOrder(oppositeOrder));

        // check long position has either been exercised or is expired
        require(
            block.timestamp > positionExpirations[longPositionId] || exercisedPositions[longPositionId],
            "Must be exercised or expired"
        );

        /*
            ~~~ EFFECTS ~~~
        */

        // send the short position to 0xdead.
        // instead of doing a standard burn by sending to 0x000...000, sending
        // to 0xdead ensures that the same position id cannot be minted again.
        transferFrom(msg.sender, address(0xdead), uint256(orderHash));

        /*
            ~~~ INTERACTIONS ~~~
        */

        if (order.isCall) {
            if (exercisedPositions[longPositionId]) {} else {}
        } else {
            if (exercisedPositions[longPositionId]) {} else {}
        }
    }

    function _transferERC20sIn(ERC20Asset[] memory assets, address from) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20(assets[i].token).safeTransferFrom(from, address(this), assets[i].tokenAmount);
        }
    }

    function _transferERC721sIn(ERC721Asset[] memory assets, address from) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC721(assets[i].token).safeTransferFrom(from, address(this), assets[i].tokenId);
        }
    }

    function _transferFloorsIn(
        address[] memory floorTokens,
        uint256[] memory floorTokenIds,
        address from
    ) internal {
        // transfer erc721 floor assets from exerciser to putty
        for (uint256 i = 0; i < floorTokens.length; i++) {
            ERC721(floorTokens[i]).safeTransferFrom(from, address(this), floorTokenIds[i]);
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
