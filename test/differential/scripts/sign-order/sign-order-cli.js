const { defaultAbiCoder } = require("ethers/lib/utils");
const { signOrder } = require("./sign-order");

const main = async () => {
  const encodedOrder = process.argv[2];
  const privateKey = process.argv[3];

  const [order] = defaultAbiCoder.decode(
    [
      "(address maker,bool isCall,bool isLong,address baseAsset,uint256 strike,uint256 premium,uint256 duration,uint256 expiration,uint256 nonce,address[] whitelist,address[] floorTokens,(address token,uint256 tokenAmount)[] erc20Assets,(address token,uint256 tokenId)[] erc721Assets)",
    ],
    encodedOrder
  );

  const signature = await signOrder(order, privateKey);

  process.stdout.write(signature);
  process.exit();
};

main();
