# Putty V2

An order-book based american options market for NFTs and ERC20s.
This project uses the foundry framework for testing/deployment.

## Getting started

```
forge install
forge test
```

## Tests

There is a full test-suite included in `./test/`. There is also a differential test suite included in `./test/differential/`. By default the differential tests are disabled. To run them follow the instructions in the README in `./test/differential/`.

## Overview

At a high level, there are 4 main entry points:

- `fillOrder(Order memory order, bytes calldata signature, uint256[] memory floorAssetTokenIds)`
- `exercise(Order memory order, uint256[] calldata floorAssetTokenIds)`
- `withdraw(Order memory order)`
- `cancel(Order memory order)`

All orders are stored off chain until they are settled on chain through `fillOrder`.
For an example of the lifecycle of these entrypoints and how they behave, see the "flow" below.

There exists much more rigorous specification files in `./specifications` explaining how the system must generally behave and the invariants that must hold.

## Flow

There are four types of orders that a user can create.

1. long put
2. short put
3. long call
4. short call

When an order is filled, 2 option contracts are minted in the form of NFTs. One NFT represents the short position, and the other NFT represents the long position. All options are fully collateralised and physically settled.

Here is an example flow for filling a long put option.

- Alice creates and signs a long put option order off-chain for 2 Bored Ape floors with a duration of 30 days, a strike of 124 WETH and a premium of 0.8 WETH
- Bob takes Alice's order and fills it by sumbitting it to the Putty smart contract using `fillOrder()`
- He sends 124 ETH to cover the strike which is converted to WETH. 0.8 WETH is transferred from Alice's wallet to Bob's wallet.
- A long NFT is sent to Alice and a short NFT is sent to Bob which represents their position in the trade
- 17 days pass and the floor price for Bored Apes has dropped to 54 ETH - (`2 * 54 = 108 ETH = 16 ETH profit`)
- Alice decides to exercise her long put contract and lock in her 16 ETH profit
  - She purchases BAYC #541 and BAYC #8765 from the open market for a combined total of 108 ETH
  - She calls exercise() on Putty and sends her BAYC id's of [#541, #8765]
  - BAYC #541 and BAYC #8765 are transferred from her wallet to Putty
  - Her long option is marked as exercised (`exercisedPositions`)
  - The 124 WETH strike is transferred to Alice
  - Alice's long option is voided and burned
- A few hours later, Bob sees that Alice has exercised her option
- He decides to withdraw (`withdraw()`) - BAYC #541 and BAYC #8765 are sent from Putty to his wallet
- His short option NFT is voided and burned

## Contact

Feel free to contact if you have questions. We are friendly :)).

out.eth - online from 08:00 UTC -> 23:00 UTC

- twitter: @outdoteth
- telegram: @outdoteth
- discord: out.eth#2001

Will usually answer within 45 mins unless I'm eating or smth. heh.
