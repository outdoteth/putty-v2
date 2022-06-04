// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/utils/cryptography/draft-EIP712.sol";
import "openzeppelin/utils/Strings.sol";
import "openzeppelin/access/Ownable.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC721.sol";

import "./PuttyV2Nft.sol";

import "forge-std/console.sol";

contract PuttyV2 is PuttyV2Nft, EIP712("Putty", "2.0"), ERC721TokenReceiver, Ownable {
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

    string public baseURI;
    uint256 public fee;

    mapping(bytes32 => bool) public cancelledOrders;
    mapping(uint256 => uint256[]) public positionFloorAssetTokenIds;
    mapping(uint256 => uint256) public positionExpirations;
    mapping(uint256 => bool) public exercisedPositions;

    constructor(string memory _baseURI, uint256 _fee) {
        setBaseURI(_baseURI);
        setFee(_fee);
    }

    function setBaseURI(string memory _baseURI) public payable onlyOwner {
        baseURI = _baseURI;
    }

    // _fee = 100% = 1000
    function setFee(uint256 _fee) public payable onlyOwner {
        require(_fee < 300, "fee must be less than 3%");

        fee = _fee;
    }

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

        // create long/short position for maker
        _mint(order.maker, uint256(orderHash));

        // create opposite long/short position for taker
        positionId = uint256(hashOppositeOrder(order));
        _mint(msg.sender, positionId);

        // save floorAssetTokenIds
        positionFloorAssetTokenIds[uint256(orderHash)] = floorAssetTokenIds;

        // save the long position expiration
        positionExpirations[order.isLong ? uint256(orderHash) : positionId] = block.timestamp + order.duration;

        /*
            ~~~ INTERACTIONS ~~~
        */

        // filling the order
        // short call - send eth for premium to maker
        // short put - send eth for premium to maker
        // long call - nothing
        // long put - send eth for strike to contract and convert to weth

        // exercising the order
        // call - send eth for strike to contract and convert to weth

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

        // check floor asset token ids length is 0 unless the position type is put
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

        /*
            ~~~ INTERACTIONS ~~~
        */

        if (order.isCall) {
            // -- exercising a call option

            // transfer strike from exerciser to putty
            ERC20(order.baseAsset).safeTransferFrom(msg.sender, address(this), order.strike);

            // transfer assets from putty to exerciser
            _transferERC20sOut(order.erc20Assets);
            _transferERC721sOut(order.erc721Assets);
            _transferFloorsOut(order.floorTokens, positionFloorAssetTokenIds[uint256(orderHash)]);
        } else {
            // -- exercising a put option

            // save the floor asset token ids to the short position
            uint256 shortPositionId = uint256(hashOppositeOrder(order));
            positionFloorAssetTokenIds[shortPositionId] = floorAssetTokenIds;

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
        require(!order.isLong, "Must be short position");

        bytes32 orderHash = hashOrder(order);

        // check msg.sender owns the position
        require(ownerOf(uint256(orderHash)) == msg.sender, "Not owner");

        uint256 longPositionId = uint256(hashOppositeOrder(order));
        bool isExercised = exercisedPositions[longPositionId];

        // check long position has either been exercised or is expired
        require(block.timestamp > positionExpirations[longPositionId] || isExercised, "Must be exercised or expired");

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

        // transfer strike to owner if put is expired or call is exercised
        if ((order.isCall && isExercised) || (!order.isCall && !isExercised)) {
            // send the fee to the owner if fee is greater than 0%
            uint256 feeAmount;
            if (fee > 0) {
                feeAmount = (order.strike * fee) / 1000;
                ERC20(order.baseAsset).safeTransfer(owner(), feeAmount);
            }

            ERC20(order.baseAsset).safeTransfer(msg.sender, order.strike - feeAmount);
        }

        // transfer assets from putty to owner if put is exercised or call is expired
        if ((order.isCall && !isExercised) || (!order.isCall && isExercised)) {
            _transferERC20sOut(order.erc20Assets);
            _transferERC721sOut(order.erc721Assets);
            _transferFloorsOut(
                order.floorTokens,
                // for call options the floor token ids are saved in the long position (in fillOrder),
                // and for put options floor tokens ids saved in the short position (in exercise)
                positionFloorAssetTokenIds[order.isCall ? longPositionId : uint256(orderHash)]
            );
        }
    }

    function cancel(Order memory order) public {
        require(msg.sender == order.maker, "Not your order");

        bytes32 orderHash = hashOrder(order);

        // mark the order as cancelled
        cancelledOrders[orderHash] = true;
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
        for (uint256 i = 0; i < floorTokens.length; i++) {
            ERC721(floorTokens[i]).safeTransferFrom(from, address(this), floorTokenIds[i]);
        }
    }

    function _transferERC20sOut(ERC20Asset[] memory assets) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20(assets[i].token).safeTransfer(msg.sender, assets[i].tokenAmount);
        }
    }

    function _transferERC721sOut(ERC721Asset[] memory assets) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC721(assets[i].token).safeTransferFrom(address(this), msg.sender, assets[i].tokenId);
        }
    }

    function _transferFloorsOut(address[] memory floorTokens, uint256[] memory floorTokenIds) internal {
        for (uint256 i = 0; i < floorTokens.length; i++) {
            ERC721(floorTokens[i]).safeTransferFrom(address(this), msg.sender, floorTokenIds[i]);
        }
    }

    function isWhitelisted(address[] memory whitelist, address target) public pure returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (target == whitelist[i]) return true;
        }

        return false;
    }

    function hashOppositeOrder(Order memory order) public view returns (bytes32 orderHash) {
        // use decode/encode to get a copy instead of reference
        Order memory oppositeOrder = abi.decode(abi.encode(order), (Order));

        // get the opposite side of the order (short/long)
        oppositeOrder.isLong = !order.isLong;
        orderHash = hashOrder(oppositeOrder);
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

    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_ownerOf[id] != address(0), "URI query for NOT_MINTED token");

        return string.concat(baseURI, Strings.toString(id));
    }
}
