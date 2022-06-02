# Differential tests

These differential tests verify that the EIP-712 implementation in PuttyV2 is correct by comparing against the ethers output.
The reference ethers scripts are located in `./scripts`.

By default, these tests are disabled. To run them:

```
forge test --no-match-path None --match-path test/differential/*.sol --ffi
```

Warning: It can take longer than 5 minutes to fully run through the whole differential test suite on a M1 mac. This is due to the fact that ffi testing is quite slow when combined with fuzz runs (default fuzz-runs is set to 1000).
