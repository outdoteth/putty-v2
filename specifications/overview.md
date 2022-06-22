# Overview

This file is somewhat experimental.
It's supposed to give a more formal definition of the desired behaviours.
Although not so formal that an actual formal spec language is used.
Just pseudo definitions.

## System state

The global state of the system:

```
// a set of all possible orders
orders: [
    state: Unfilled | Filled | Exercised | Expired | Cancelled
    owner: address | null
    expiration: timestamp | null
    floor token ids: number[] | null
    side: Long | Short
    type: Call | Put
]
```

## Invariants

The state of an order can only progress in the following ways:

```
Unfilled -> Filled -> Exercised
Unfilled -> Filled -> Expired
Unfilled -> Cancelled
```

The expiration of an order can only progress in the following way:

```
if state == Unfilled:
    null -> timestamp
```

The floor token ids of an order can only progress in the following ways:

```
if state == Unfilled & side == Long & type == Call:
    null -> number[]

if state == Filled & side == Short & type == Put:
    null -> number[]
```

The owner of an order can progress in the following ways:

```
if state == Filled | state == Expired | (state == Exercised & side == Short):
    address -> address

if state == Unfilled:
    null -> address
```

Aside from these system state changes, nothing else should be able to be updated.
Everything else in the system should be constant.

## Methods
