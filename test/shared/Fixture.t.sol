// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "src/PuttyV2.sol";

abstract contract Fixture is Test {
    PuttyV2 internal p;

    address internal babe;
    address internal bob;
    string internal checkpointLabel;
    uint256 internal checkpointGasLeft;

    constructor() {
        p = new PuttyV2();

        babe = address(0xbabe);
        vm.label(babe, "Babe");

        bob = address(0xb0b);
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
}
