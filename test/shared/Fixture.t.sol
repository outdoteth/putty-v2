// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/PuttyV2.sol";

abstract contract Fixture is Test {
    PuttyV2 internal p;

    uint256 internal babePrivateKey;
    uint256 internal bobPrivateKey;
    address internal babe;
    address internal bob;
    string internal checkpointLabel;
    uint256 internal checkpointGasLeft;

    address[] internal __whitelist;
    address[] internal __floorTokens;
    PuttyV2.ERC20Asset[] internal __erc20Assets;
    PuttyV2.ERC721Asset[] internal __erc721Assets;
    uint256[] internal __floorAssetTokenIds;

    constructor() {
        p = new PuttyV2();

        babePrivateKey = uint256(0xbabe);
        babe = vm.addr(babePrivateKey);
        vm.label(babe, "Babe");

        bobPrivateKey = uint256(0xb0b);
        bob = vm.addr(bobPrivateKey);
        vm.label(bob, "Bob");

        // make sure timestamp is not 0
        vm.warp(0xffff);
    }

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;
        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 20_000;

        console.log(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }

    function signOrder(uint256 privateKey, PuttyV2.Order memory order) internal returns (bytes memory signature) {
        bytes32 digest = p.hashOrder(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function defaultOrder() internal view returns (PuttyV2.Order memory order) {
        order = PuttyV2.Order({
            maker: babe,
            isCall: true,
            isLong: true,
            baseAsset: bob,
            strike: 1,
            premium: 2,
            duration: 3,
            expiration: 4,
            nonce: 5,
            whitelist: __whitelist,
            floorTokens: __floorTokens,
            erc20Assets: __erc20Assets,
            erc721Assets: __erc721Assets
        });
    }
}
