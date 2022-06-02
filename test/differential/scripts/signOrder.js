const ethers = require("ethers");
const { _TypedDataEncoder, defaultAbiCoder } = require("ethers/lib/utils");
const { keccak256 } = require("@ethersproject/keccak256");
const { toUtf8Bytes } = require("@ethersproject/strings");

function id(text) {
  return keccak256(toUtf8Bytes(text));
}

function encodeType(name, fields) {
  return `${name}(${fields.map(({ name, type }) => type + " " + name).join(",")})`;
}

const main = async () => {
  const domain = {
    name: "Putty",
    version: "2.0",
    chainId: 31337,
    verifyingContract: "0xce71065d4017f316ec606fe4422e11eb2c47c246",
  };

  // The named list of all type definitions
  const types = {
    Order: [
      { name: "maker", type: "address" },
      { name: "isCall", type: "bool" },
      { name: "isLong", type: "bool" },
      { name: "baseAsset", type: "address" },
      { name: "strike", type: "uint256" },
      { name: "premium", type: "uint256" },
      { name: "duration", type: "uint256" },
      { name: "expiration", type: "uint256" },
      { name: "nonce", type: "uint256" },
      { name: "whitelist", type: "address[]" },
      { name: "floorTokens", type: "address[]" },
      { name: "erc20Assets", type: "ERC20Asset[]" },
      { name: "erc721Assets", type: "ERC721Asset[]" },
    ],
    ERC20Asset: [
      { name: "token", type: "address" },
      { name: "tokenAmount", type: "uint256" },
    ],
    ERC721Asset: [
      { name: "token", type: "address" },
      { name: "tokenId", type: "uint256" },
    ],
  };

  const encodedOrder = process.argv[2];
  const [order] = defaultAbiCoder.decode(
    [
      "(address maker,bool isCall,bool isLong,address baseAsset,uint256 strike,uint256 premium,uint256 duration,uint256 expiration,uint256 nonce,address[] whitelist,address[] floorTokens,(address token,uint256 tokenAmount)[] erc20Assets,(address token,uint256 tokenId)[] erc721Assets)",
    ],
    encodedOrder
  );

  const hash = _TypedDataEncoder.hash(domain, types, order);

  process.stdout.write(hash);

  // const addressList = [babe, babe];
  // const numberList = [100];
  // const value = {
  //   maker: babe,
  //   isCall: false,
  //   isLong: false,
  //   baseAsset: bob,
  //   strike: 1,
  //   premium: 2,
  //   duration: 3,
  //   expiration: 4,
  //   nonce: 5,
  //   whitelist: addressList,
  //   floorTokens: addressList,
  //   erc20Tokens: addressList,
  //   erc20Amounts: numberList,
  //   erc20Assets: [{ token: babe, tokenAmount: 7 }],
  //   erc721Assets: [{ token: babe, tokenId: 6 }],
  // };

  // const hashedDomain = _TypedDataEncoder.hashDomain(domain);
  // const encoded = _TypedDataEncoder.encode(domain, types, order);
  // const primaryType = _TypedDataEncoder.getPrimaryType(types);
  // const encoder = _TypedDataEncoder.from(types);
  // console.log("encoding", encoder.encode(value));
  // console.log("type hash", id(encoder._types["Order"]));
  // console.log("domain", hashedDomain);
  // console.log("order hash", encoded);
  // console.log("final hash", hash);
  // console.log("Primary", primaryType);
};

main();
