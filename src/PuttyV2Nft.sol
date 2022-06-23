// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "solmate/tokens/ERC721.sol";
import "openzeppelin/utils/Strings.sol";

// removes balanceOf modifications
// questionable tradeoff but given our use-case it's reasonable
abstract contract PuttyV2Nft is ERC721("Putty", "OPUT") {
    // remove balanceOf modifications
    function _mint(address to, uint256 id) internal override {
        require(to != address(0), "INVALID_RECIPIENT");
        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    // burns a token without checking owner address is not 0
    // and removes balanceOf modifications
    function _burn(uint256 id) internal override {
        address owner = _ownerOf[id];

        delete _ownerOf[id];
        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    // set balanceOf to max for all users
    function balanceOf(address owner) public pure override returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");
        return type(uint256).max;
    }
}
