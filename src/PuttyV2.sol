// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/**

    ██████╗ ██╗   ██╗████████╗████████╗██╗   ██╗    ██╗   ██╗██████╗ 
    ██╔══██╗██║   ██║╚══██╔══╝╚══██╔══╝╚██╗ ██╔╝    ██║   ██║╚════██╗
    ██████╔╝██║   ██║   ██║      ██║    ╚████╔╝     ██║   ██║ █████╔╝
    ██╔═══╝ ██║   ██║   ██║      ██║     ╚██╔╝      ╚██╗ ██╔╝██╔═══╝ 
    ██║     ╚██████╔╝   ██║      ██║      ██║        ╚████╔╝ ███████╗
    ╚═╝      ╚═════╝    ╚═╝      ╚═╝      ╚═╝         ╚═══╝  ╚══════╝
    
                                
            _..._               
          .'     '.      _       
         /    .-""-\   _/ \ 
       .-|   /:.   |  |   |   bussin
       |  \  |:.   /.-'-./
       | .-'-;:__.'    =/
       .'=  *=|     _.='
      /   _.  |    ;        minister you satoshi
     ;-.-'|    \   |
    /   | \    _\  _\
    \__/'._;.  ==' ==\
             \    \   |
             /    /   / 
             /-._/-._/
      jgs    \   `\  \
              `-._/._/


    this is a public good.
    by out.eth and tamagoyaki
    
 */

import "./lib/IWETH.sol";

import "openzeppelin/utils/cryptography/SignatureChecker.sol";
import "openzeppelin/utils/cryptography/draft-EIP712.sol";
import "openzeppelin/utils/Strings.sol";
import "openzeppelin/access/Ownable.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC721.sol";

import "./PuttyV2Nft.sol";

/**
    @title PuttyV2
    @author out.eth
    @notice An otc erc721 and erc20 option market.
 */
contract PuttyV2 is PuttyV2Nft, EIP712("Putty", "2.0"), ERC721TokenReceiver, Ownable {
    /* ~~~ TYPES ~~~ */

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

    /* ~~~ STATE VARIABLES ~~~ */

    /**
        @dev ERC721Asset type hash used for EIP-712 encoding.
     */
    bytes32 public constant ERC721ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC721Asset(address token,uint256 tokenId)"));

    /**
        @dev ERC721Asset type hash used for EIP-712 encoding.
     */
    bytes32 public constant ERC20ASSET_TYPE_HASH =
        keccak256(abi.encodePacked("ERC20Asset(address token,uint256 tokenAmount)"));

    /**
        @dev ERC721Asset type hash used for EIP-712 encoding.
     */
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

    /**
        @dev Contract address for Wrapped Ethereum.
     */
    address public immutable weth;

    /**
        @dev baseURI used to generate the tokenURI for PuttyV2 NFTs.
    */
    string public baseURI;

    /**
        @notice Fee rate that is applied on exercise.
    */
    uint256 public fee;

    /**
        @notice Whether or not an order has been cancelled. Maps 
                from orderHash to isCancelled.
    */
    mapping(bytes32 => bool) public cancelledOrders;

    /**
        @notice The current expiration timestamp of a position. Maps 
                from positionId to an expiration unix timestamp.
    */
    mapping(uint256 => uint256) public positionExpirations;

    /**
        @notice Whether or not a position has been exercised. Maps 
                from positionId to isExercised.
    */
    mapping(uint256 => bool) public exercisedPositions;

    /**
        @notice The floor asset token ids for a position. Maps from 
                positionId to floor asset token ids. This should only 
                be set for a long call position in `fillOrder`, or for 
                a short put position in `exercise`.
    */
    mapping(uint256 => uint256[]) public positionFloorAssetTokenIds;

    /* ~~~ EVENTS ~~~ */

    /**
        @notice Emitted when a new base URI is set.
        @param baseURI The new baseURI.
     */
    event NewBaseURI(string baseURI);

    /**
        @notice Emitted when a new fee is set.
        @param fee The new fee.
     */
    event NewFee(uint256 fee);

    /**
        @notice Emitted when an order is filled.
        @param orderHash The hash of the order that was filled.
        @param floorAssetTokenIds The floor asset token ids that were used.
        @param order The order that was filled.
     */
    event FilledOrder(bytes32 indexed orderHash, uint256[] floorAssetTokenIds, Order order);

    /**
        @notice Emitted when an order is exercised.
        @param orderHash The hash of the order that was exercised.
        @param floorAssetTokenIds The floor asset token ids that were used.
        @param order The order that was exercised.
     */
    event ExercisedOrder(bytes32 indexed orderHash, uint256[] floorAssetTokenIds, Order order);

    /**
        @notice Emitted when an order is withdrawn.
        @param orderHash The hash of the order that was withdrawn.
        @param order The order that was withdrawn.
     */
    event WithdrawOrder(bytes32 indexed orderHash, Order order);

    /**
        @notice emitted When an order is cancelled.
        @param orderHash The hash of the order that was cancelled.
        @param order The order that was cancelled.
     */
    event CancelledOrder(bytes32 indexed orderHash, Order order);

    constructor(
        string memory _baseURI,
        uint256 _fee,
        address _weth
    ) {
        setBaseURI(_baseURI);
        setFee(_fee);
        weth = _weth;
    }

    /* ~~~ ADMIN FUNCTIONS ~~~ */

    /**
        @notice Sets a new baseURI that is used in the construction
                of the tokenURI for each NFT position. Admin/DAO only.
        @param _baseURI The new base URI to use.
     */
    function setBaseURI(string memory _baseURI) public payable onlyOwner {
        baseURI = _baseURI;

        emit NewBaseURI(_baseURI);
    }

    /**
        @notice Sets a new fee rate that is applied on exercise. The
                fee has a precision of 1 decimal. e.g. 1000 = 100%,
                100 = 10%, 1 = 0.1%. Admin/DAO only.
        @param _fee The new fee rate to use.
     */
    function setFee(uint256 _fee) public payable onlyOwner {
        require(_fee < 30, "fee must be less than 3%");

        fee = _fee;

        emit NewFee(_fee);
    }

    /*
        ~~~ MAIN LOGIC FUNCTIONS ~~~

        Standard lifecycle:
            [1] fillOrder()
            [2] exercise()
            [3] withdraw()

            * It is also possible to cancel() an order before fillOrder()
    */

    /**
        @notice Fills an offchain order and settles it onchain. Mints two
                NFTs that represent the long and short position for the order.
        @param order The order to fill.
        @param signature The signature for the order. Signature must recover to order.maker.
        @param floorAssetTokenIds The floor asset token ids to use. Should only be set 
               when filling a long call order.
        @return positionId The id of the position NFT that the msg.sender receives.
     */
    function fillOrder(
        Order memory order,
        bytes calldata signature,
        uint256[] memory floorAssetTokenIds
    ) public payable returns (uint256 positionId) {
        /* ~~~ CHECKS ~~~ */

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

        // check base asset exists
        require(order.baseAsset.code.length > 0, "baseAsset is not contract");

        // check floor asset token ids length is 0 unless the order `type` is call and `side` is long
        order.isCall && order.isLong
            ? require(floorAssetTokenIds.length == order.floorTokens.length, "Wrong amount of floor tokenIds")
            : require(floorAssetTokenIds.length == 0, "Invalid floor tokens length");

        /*  ~~~ EFFECTS ~~~ */

        // create long/short position for maker
        _mint(order.maker, uint256(orderHash));

        // create opposite long/short position for taker
        bytes32 oppositeOrderHash = hashOppositeOrder(order);
        positionId = uint256(oppositeOrderHash);
        _mint(msg.sender, positionId);

        // save floorAssetTokenIds if filling a long call order
        if (order.isLong && order.isCall) {
            positionFloorAssetTokenIds[uint256(orderHash)] = floorAssetTokenIds;
        }

        // save the long position expiration
        positionExpirations[order.isLong ? uint256(orderHash) : positionId] = block.timestamp + order.duration;

        emit FilledOrder(orderHash, floorAssetTokenIds, order);

        /* ~~~ INTERACTIONS ~~~ */

        // transfer premium to whoever is short from whomever is long
        if (order.isLong) {
            ERC20(order.baseAsset).safeTransferFrom(order.maker, msg.sender, order.premium);
        } else {
            // handle the case where the user uses native ETH instead of WETH to pay the premium
            if (weth == order.baseAsset && msg.value > 0) {
                // check enough ETH was sent to cover the premium
                require(msg.value == order.premium, "Incorrect ETH amount sent");

                // convert ETH to WETH and send premium to maker
                // converting to WETH instead of forwarding native ETH to the maker has two benefits;
                // 1) active market makers will mostly be using WETH not native ETH
                // 2) attack surface for re-entrancy is reduced
                IWETH(weth).deposit{value: msg.value}();
                IWETH(weth).transfer(order.maker, msg.value);
            } else {
                ERC20(order.baseAsset).safeTransferFrom(msg.sender, order.maker, order.premium);
            }
        }

        // filling short put: transfer strike from maker to contract
        if (!order.isLong && !order.isCall) {
            ERC20(order.baseAsset).safeTransferFrom(order.maker, address(this), order.strike);
            return positionId;
        }

        // filling long put: transfer strike from taker to contract
        if (order.isLong && !order.isCall) {
            // handle the case where the taker uses native ETH instead of WETH to deposit the strike
            if (weth == order.baseAsset && msg.value > 0) {
                // check enough ETH was sent to cover the strike
                require(msg.value == order.strike, "Incorrect ETH amount sent");

                // convert ETH to WETH
                // we convert the strike ETH to WETH so that the logic in exercise() works
                // - because exercise() assumes an ERC20 interface on the base asset.
                IWETH(weth).deposit{value: msg.value}();
            } else {
                ERC20(order.baseAsset).safeTransferFrom(msg.sender, address(this), order.strike);
            }

            return positionId;
        }

        // filling short call: transfer assets from maker to contract
        if (!order.isLong && order.isCall) {
            _transferERC20sIn(order.erc20Assets, order.maker);
            _transferERC721sIn(order.erc721Assets, order.maker);
            return positionId;
        }

        // filling long call: transfer assets from taker to contract
        if (order.isLong && order.isCall) {
            _transferERC20sIn(order.erc20Assets, msg.sender);
            _transferERC721sIn(order.erc721Assets, msg.sender);
            _transferFloorsIn(order.floorTokens, floorAssetTokenIds, msg.sender);
            return positionId;
        }
    }

    /**
        @notice Exercises a long order and also burns the long position NFT which 
                represents it.
        @param order The order of the position to exercise.
        @param floorAssetTokenIds The floor asset token ids to use. Should only be set 
               when exercising a put order.
     */
    function exercise(Order memory order, uint256[] calldata floorAssetTokenIds) public payable {
        /* ~~~ CHECKS ~~~ */

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

        /* ~~~ EFFECTS ~~~ */

        // send the long position to 0xdead.
        // instead of doing a standard burn by sending to 0x000...000, sending
        // to 0xdead ensures that the same position id cannot be minted again.
        transferFrom(msg.sender, address(0xdead), uint256(orderHash));

        // mark the position as exercised
        exercisedPositions[uint256(orderHash)] = true;

        emit ExercisedOrder(orderHash, floorAssetTokenIds, order);

        /* ~~~ INTERACTIONS ~~~ */

        if (order.isCall) {
            // -- exercising a call option

            // transfer strike from exerciser to putty
            // handle the case where the taker uses native ETH instead of WETH to pay the strike
            if (weth == order.baseAsset && msg.value > 0) {
                // check enough ETH was sent to cover the strike
                require(msg.value == order.strike, "Incorrect ETH amount sent");

                // convert ETH to WETH
                // we convert the strike ETH to WETH so that the logic in withdraw() works
                // - because withdraw() assumes an ERC20 interface on the base asset.
                IWETH(weth).deposit{value: msg.value}();
            } else {
                ERC20(order.baseAsset).safeTransferFrom(msg.sender, address(this), order.strike);
            }

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

    /**
        @notice Withdraws the assets from a short order and also burns the short position 
                that represents it. The assets that are withdrawn are dependent on whether 
                the order is exercised or expired and if the order is a put or call.
        @param order The order to withdraw.
     */
    function withdraw(Order memory order) public {
        /* ~~~ CHECKS ~~~ */

        // check order is short
        require(!order.isLong, "Must be short position");

        bytes32 orderHash = hashOrder(order);

        // check msg.sender owns the position
        require(ownerOf(uint256(orderHash)) == msg.sender, "Not owner");

        uint256 longPositionId = uint256(hashOppositeOrder(order));
        bool isExercised = exercisedPositions[longPositionId];

        // check long position has either been exercised or is expired
        require(block.timestamp > positionExpirations[longPositionId] || isExercised, "Must be exercised or expired");

        /* ~~~ EFFECTS ~~~ */

        // send the short position to 0xdead.
        // instead of doing a standard burn by sending to 0x000...000, sending
        // to 0xdead ensures that the same position id cannot be minted again.
        transferFrom(msg.sender, address(0xdead), uint256(orderHash));

        emit WithdrawOrder(orderHash, order);

        /* ~~~ INTERACTIONS ~~~ */

        // transfer strike to owner if put is expired or call is exercised
        if ((order.isCall && isExercised) || (!order.isCall && !isExercised)) {
            // send the fee to the owner if fee is greater than 0%
            uint256 feeAmount;
            if (fee > 0) {
                feeAmount = (order.strike * fee) / 1000;
                ERC20(order.baseAsset).safeTransfer(owner(), feeAmount);
            }

            ERC20(order.baseAsset).safeTransfer(msg.sender, order.strike - feeAmount);
            return;
        }

        // transfer assets from putty to owner if put is exercised or call is expired
        if ((order.isCall && !isExercised) || (!order.isCall && isExercised)) {
            _transferERC20sOut(order.erc20Assets);
            _transferERC721sOut(order.erc721Assets);
            _transferFloorsOut(
                order.floorTokens,
                // for call options the floor token ids are saved in the long position in fillOrder(),
                // and for put options the floor tokens ids are saved in the short position in exercise()
                positionFloorAssetTokenIds[order.isCall ? longPositionId : uint256(orderHash)]
            );

            return;
        }
    }

    /**
        @notice Cancels an order which prevents it from being filled in the future.
        @param order The order to cancel.
     */
    function cancel(Order memory order) public {
        require(msg.sender == order.maker, "Not your order");

        bytes32 orderHash = hashOrder(order);

        // mark the order as cancelled
        cancelledOrders[orderHash] = true;

        emit CancelledOrder(orderHash, order);
    }

    /* ~~~ PERIPHERY LOGIC FUNCTIONS ~~~ */

    /**
        @notice Batch fills multiple orders.
        @param orders The order to fill.
        @param signatures The signatures to use for each respective order.
        @param floorAssetTokenIds The floorAssetTokenIds to use for each respective order.
        @return positionIds The ids of the position NFT that the msg.sender receives.
     */
    function batchFillOrder(
        Order[] memory orders,
        bytes[] calldata signatures,
        uint256[][] memory floorAssetTokenIds
    ) public returns (uint256[] memory positionIds) {
        require(orders.length == signatures.length, "Length mismatch in input");
        require(signatures.length == floorAssetTokenIds.length, "Length mismatch in input");

        positionIds = new uint256[](orders.length);

        for (uint256 i = 0; i < orders.length; i++) {
            positionIds[i] = fillOrder(orders[i], signatures[i], floorAssetTokenIds[i]);
        }
    }

    /**
        @notice Accepts a counter offer for an order. It fills the counter offer, and then
                cancels the original order that the counter offer was made for.
        @dev There is no need for floorTokenIds here because there is no situation in which
             it makes sense to have them when accepting counter offers. When accepting a counter 
             offer for a short call order, the complementary long call order already knows what 
             tokenIds are used in the short call.
        @param order The counter offer to accept.
        @param signature The signature for the counter offer.
        @param originalOrder The original order that the counter was made for.
        @return positionId The id of the position NFT that the msg.sender receives.
     */
    function acceptCounterOffer(
        Order memory order,
        bytes calldata signature,
        Order memory originalOrder
    ) public payable returns (uint256 positionId) {
        // accept the counter offer
        uint256[] memory floorAssetTokenIds = new uint256[](0);
        positionId = fillOrder(order, signature, floorAssetTokenIds);

        // cancel the original order
        cancel(originalOrder);
    }

    /* ~~~ HELPER FUNCTIONS ~~~ */

    /**
        @notice Transfers an array of erc20s into the contract from an address.
        @param assets The erc20 tokens and amounts to transfer in.
        @param from Who to transfer the erc20 assets from.
     */
    function _transferERC20sIn(ERC20Asset[] memory assets, address from) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            address token = assets[i].token;
            require(token.code.length > 0, "ERC20: Token is not contract");
            ERC20(token).safeTransferFrom(from, address(this), assets[i].tokenAmount);
        }
    }

    /**
        @notice Transfers an array of erc721s into the contract from an address.
        @param assets The erc721 tokens and token ids to transfer in.
        @param from Who to transfer the erc721 assets from.
     */
    function _transferERC721sIn(ERC721Asset[] memory assets, address from) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC721(assets[i].token).safeTransferFrom(from, address(this), assets[i].tokenId);
        }
    }

    /**
        @notice Transfers an array of erc721 floor tokens into the contract from an address.
        @param floorTokens The contract addresses of each erc721.
        @param floorTokenIds The token id of each erc721.
        @param from Who to transfer the floor tokens from.
     */
    function _transferFloorsIn(
        address[] memory floorTokens,
        uint256[] memory floorTokenIds,
        address from
    ) internal {
        for (uint256 i = 0; i < floorTokens.length; i++) {
            ERC721(floorTokens[i]).safeTransferFrom(from, address(this), floorTokenIds[i]);
        }
    }

    /**
        @notice Transfers an array of erc20 tokens to the msg.sender.
        @param assets The erc20 tokens and amounts to send.
     */
    function _transferERC20sOut(ERC20Asset[] memory assets) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC20(assets[i].token).safeTransfer(msg.sender, assets[i].tokenAmount);
        }
    }

    /**
        @notice Transfers an array of erc721 tokens to the msg.sender.
        @param assets The erc721 tokens and token ids to send.
     */
    function _transferERC721sOut(ERC721Asset[] memory assets) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            ERC721(assets[i].token).safeTransferFrom(address(this), msg.sender, assets[i].tokenId);
        }
    }

    /**
        @notice Transfers an array of erc721 floor tokens to the msg.sender.
        @param floorTokens The contract addresses for each floor token.
        @param floorTokenIds The token id of each floor token.
     */
    function _transferFloorsOut(address[] memory floorTokens, uint256[] memory floorTokenIds) internal {
        for (uint256 i = 0; i < floorTokens.length; i++) {
            ERC721(floorTokens[i]).safeTransferFrom(address(this), msg.sender, floorTokenIds[i]);
        }
    }

    /**
        @notice Checks whether or not an address exists in the whitelist.
        @param whitelist The whitelist to check against.
        @param target The target address to check.
        @return If it exists in the whitelist or not.
     */
    function isWhitelisted(address[] memory whitelist, address target) public pure returns (bool) {
        for (uint256 i = 0; i < whitelist.length; i++) {
            if (target == whitelist[i]) return true;
        }

        return false;
    }

    /**
        @notice Get the orderHash for a complementary short/long order - e.g for a long order,
                this returns the hash of it's opposite short order.
        @param order The order to find the complementary long/short hash for.
        @return orderHash The hash of the opposite order.
     */
    function hashOppositeOrder(Order memory order) public view returns (bytes32 orderHash) {
        // use decode/encode to get a copy instead of reference
        Order memory oppositeOrder = abi.decode(abi.encode(order), (Order));

        // get the opposite side of the order (short/long)
        oppositeOrder.isLong = !order.isLong;
        orderHash = hashOrder(oppositeOrder);
    }

    /* ~~~ EIP-712 HELPERS ~~~ */

    /**
        @notice Hashes an order based on the eip-712 encoding scheme.
        @param order The order to hash.
        @return orderHash The eip-712 compliant hash of the order.
     */
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

    /**
        @notice Encodes an array of erc721 assets following the eip-712 encoding scheme.
        @param arr Array of erc721 assets to hash.
        @return encoded The eip-712 encoded array of erc721 assets.
     */
    function encodeERC721Assets(ERC721Asset[] memory arr) public pure returns (bytes memory encoded) {
        for (uint256 i = 0; i < arr.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                keccak256(abi.encode(ERC721ASSET_TYPE_HASH, arr[i].token, arr[i].tokenId))
            );
        }
    }

    /**
        @notice Encodes an array of erc20 assets following the eip-712 encoding scheme.
        @param arr Array of erc20 assets to hash.
        @return encoded The eip-712 encoded array of erc20 assets.
     */
    function encodeERC20Assets(ERC20Asset[] memory arr) public pure returns (bytes memory encoded) {
        for (uint256 i = 0; i < arr.length; i++) {
            encoded = abi.encodePacked(
                encoded,
                keccak256(abi.encode(ERC20ASSET_TYPE_HASH, arr[i].token, arr[i].tokenAmount))
            );
        }
    }

    /**
        @return The domain seperator used when calculating the eip-712 hash.
     */
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /* ~~~ OVERRIDES ~~~ */

    /**
        @notice Gets the token URI for an NFT.
        @param id The id of the position NFT.
        @return The tokenURI of the position NFT.
     */
    function tokenURI(uint256 id) public view override returns (string memory) {
        require(_ownerOf[id] != address(0), "URI query for NOT_MINTED token");

        return string.concat(baseURI, Strings.toString(id));
    }
}
