import {
  AptosClient,
  AptosAccount,
  CoinClient,
  TokenClient,
  FaucetClient,
  HexString,
  TxnBuilderTypes,
  BCS,
} from "aptos";
import * as fs from "fs";
import { sha3_256 } from "@noble/hashes/sha3";
import { exec } from "child_process";

// const NODE_URL = "http://127.0.0.1:8080";
// const FAUCET_URL = "http://127.0.0.1:8081";
const NODE_URL: string = "https://fullnode.devnet.aptoslabs.com/v1/"
const FAUCET_URL = "https://faucet.devnet.aptoslabs.com"
let alice: AptosAccount;
let bob: AptosAccount;
let cas: AptosAccount;
let moduleOwner: AptosAccount;
const client = new AptosClient(NODE_URL);
const faucetClient = new FaucetClient(NODE_URL, FAUCET_URL);
const coinClient = new CoinClient(client);
const tokenClient = new TokenClient(client);
const initialFund = 100_000_000;

// Token data
const aliceCollection = {
  name: "alice collection",
  description: "this is alice collection",
  uri: "https://xyz.com",
};
const bobCollection = {
  name: "bob collection",
  description: "this is bob collection",
  uri: "https://xyz.com",
};
const casCollection = {
  name: "cas collection",
  description: "this is cas collection",
  uri: "https://xyz.com",
};

const aliceTokens = [
  {
    name: "first token",
    description: "This is my first token",
    uri: "https://xyz.com",
    supply: 1,
  },
  {
    name: "second token",
    description: "This is my second token",
    uri: "https://xyz.com",
    supply: 1,
  },
];

type TokenDataId = {
  creator: string;
  collection: string;
  name: string;
};

type TokenId = {
  property_version: string;
  token_data_id: TokenDataId;
};

type WithdrawCapability = {
  amount: string;
  expiration_sec: string;
  token_id: TokenId;
  token_owner: string;
};

type AuctionItem = {
  current_bid?: { value: string };
  current_bidder?: string;
  end_time?: string;
  min_selling_price?: string;
  start_time?: string;
  token?: TokenId;
  withdrawCapability?: WithdrawCapability;
};

type ListingItem = {
  list_price?: string;
  end_time?: string;
  token?: TokenId;
  withdrawCapability?: WithdrawCapability;
};

type Table = {
  items?: { handle: string };
};

function stringToHex(text: string) {
  const encoder = new TextEncoder();
  const encoded = encoder.encode(text);
  return Array.from(encoded, (i) => i.toString(16).padStart(2, "0")).join("");
}

function fetchResourceAccount(initiator: HexString, receiver: HexString) {
  const source = BCS.bcsToBytes(
    TxnBuilderTypes.AccountAddress.fromHex(initiator)
  );
  const seed = BCS.bcsToBytes(TxnBuilderTypes.AccountAddress.fromHex(receiver));

  const originBytes = new Uint8Array(source.length + seed.length + 1);

  originBytes.set(source);
  originBytes.set(seed, source.length);
  originBytes.set([255], source.length + seed.length);

  const hash = sha3_256.create();
  hash.update(originBytes);
  return HexString.fromUint8Array(hash.digest());
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe("set up account, mint tokens and publish module", () => {
  it("Is able to fund the accounts", async () => {
    // if (NODE_URL === "")
    const moduleOwnerKeys = {
      address:
        "0x7f3d5a9cb25dcd7b3f9a73d266b96b62c13e0326abc0755c7f619ed2b908e98f",
      publicKeyHex:
        "0x12fcf065ffbea809331f69f03baf32c023b8630683e1533f71ca09e12e2c722f",
      privateKeyHex: `0x45bbfbcc3f1b3fc66c2c0a604e2f71462fc9c4825d4a83beab7a0609f1c4f4ab`,
    };

    moduleOwner = AptosAccount.fromAptosAccountObject(moduleOwnerKeys);
    alice = new AptosAccount();
    bob = new AptosAccount();
    cas = new AptosAccount();

    await faucetClient.fundAccount(moduleOwner.address(), initialFund);
    await faucetClient.fundAccount(alice.address(), initialFund);
    await faucetClient.fundAccount(bob.address(), initialFund);
    await faucetClient.fundAccount(cas.address(), initialFund);
    const aliceBalance = await coinClient.checkBalance(alice);
    const bobBalance = await coinClient.checkBalance(bob);
    const casBalance = await coinClient.checkBalance(cas);
    expect(Number(aliceBalance)).toBe(initialFund);
    expect(Number(bobBalance)).toBe(initialFund);
    expect(Number(casBalance)).toBe(initialFund);
    console.log("alice address: ", alice.address());
    console.log("bob address: ", bob.address());
  });

  it("is able to mint some tokens", async () => {
    // Create a collection
    try {
      const tx = await tokenClient.createCollection(
        alice,
        aliceCollection.name,
        aliceCollection.description,
        aliceCollection.uri
      );
      await client.waitForTransaction(tx);
      const collectionData = await tokenClient.getCollectionData(
        alice.address(),
        aliceCollection.name
      );
      expect(collectionData.name).toBe(aliceCollection.name);
    } catch (error) {
      console.log(error);
      throw error;
    }
  });

  it("is able to mint some tokens", async () => {
    try {
      const tx1 = await tokenClient.createToken(
        alice,
        aliceCollection.name,
        aliceTokens[0].name,
        aliceTokens[0].description,
        aliceTokens[0].supply,
        aliceTokens[0].uri
      );
      await client.waitForTransaction(tx1, { checkSuccess: true });
      const tx2 = await tokenClient.createToken(
        alice,
        aliceCollection.name,
        aliceTokens[1].name,
        aliceTokens[1].description,
        aliceTokens[1].supply,
        aliceTokens[1].uri
      );
      await client.waitForTransaction(tx2, { checkSuccess: true });
      const aliceToken1Data = await tokenClient.getTokenData(
        alice.address(),
        aliceCollection.name,
        aliceTokens[0].name
      );
      const aliceToken2Data = await tokenClient.getTokenData(
        alice.address(),
        aliceCollection.name,
        aliceTokens[1].name
      );
      expect(aliceToken1Data.name).toBe(aliceTokens[0].name);
      expect(aliceToken2Data.name).toBe(aliceTokens[1].name);
    } catch (error) {
      console.log(error);
      throw error;
    }
  });
  it("Publish the package", async () => {
    const packageMetadata = fs.readFileSync(
      "./build/marketplace/package-metadata.bcs"
    );
    const moduleData2 = fs.readFileSync(
      "./build/marketplace/bytecode_modules/FixedPriceSale.mv"
    );
    const moduleData1 = fs.readFileSync(
      "./build/marketplace/bytecode_modules/Auction.mv"
    );
    let txnHash = await client.publishPackage(
      moduleOwner,
      new HexString(packageMetadata.toString("hex")).toUint8Array(),
      [
        new TxnBuilderTypes.Module(
          new HexString(moduleData1.toString("hex")).toUint8Array()
        ),
        new TxnBuilderTypes.Module(
          new HexString(moduleData2.toString("hex")).toUint8Array()
        ),
      ]
    );
    console.log("published hash: ", txnHash);
    try {
      await client.waitForTransaction(txnHash, { checkSuccess: true });
    } catch (error) {
      console.log(error);
      throw error;
    }
    const modules = await client.getAccountModules(moduleOwner.address());
    const hasFixedPriceModule = modules.some(
      (m) => m.abi?.name === "FixedPriceSale"
    );
    const hasAuctionModule = modules.some((m) => m.abi?.name === "Auction");
    expect(hasFixedPriceModule).toBe(true);
    expect(hasAuctionModule).toBe(true);
  });
});

describe("Auction House Transaction", () => {
  it("can initialize auction", async () => {
    // For a custom transaction, pass the function name with deployed address
    // syntax: deployed_address::module_name::struct_name
    let expirationTime = 0;
    if (NODE_URL == "http://127.0.0.1:8080") 
      expirationTime = 2000000; 
    else
      expirationTime = 8000000;
    const data = [
      alice.address(),
      aliceCollection.name,
      aliceTokens[0].name,
      100,
      expirationTime,
      0,
    ];
    const payload = {
      arguments: data,
      function: `${moduleOwner.address()}::Auction::initialize_auction`,
      type: "entry_function_payload",
      type_arguments: ["0x1::aptos_coin::AptosCoin"],
    };
    try {
      const transaction = await client.generateTransaction(
        alice.address(),
        payload
      );
      const signature = await client.signTransaction(alice, transaction);
      const tx = await client.submitTransaction(signature);
      await client.waitForTransaction(tx.hash, { checkSuccess: true });
      const resource = await client.getAccountResource(
        alice.address(),
        `${moduleOwner.address()}::Auction::AuctionItem<0x1::aptos_coin::AptosCoin>`
      );
      const aliceData: Table = resource.data;
      const handle = aliceData.items?.handle;

      const tokenDataId: TokenDataId = {
        creator: alice.address().toShortString(),
        collection: aliceCollection.name,
        name: aliceTokens[0].name,
      };

      const key: TokenId = {
        token_data_id: tokenDataId,
        property_version: "0",
      };

      if (handle != null) {
        const item: AuctionItem = await client.getTableItem(handle, {
          key: key,
          key_type: "0x3::token::TokenId",
          value_type: `${moduleOwner.address()}::Auction::Item<0x1::aptos_coin::AptosCoin>`,
        });
        expect(Number(item.min_selling_price)).toBe(100);
      }
      else {
        throw "Resource does not exist";
      }
    } catch (error) {
      throw error;
    }
  });

  it("can bid on auctioned item", async () => {
    const data = [
      alice.address(),
      alice.address(),
      aliceCollection.name,
      aliceTokens[0].name,
      0,
      101,
    ];
    const payload = {
      arguments: data,
      function: `${moduleOwner.address()}::Auction::bid`,
      type: "entry_function_payload",
      type_arguments: ["0x1::aptos_coin::AptosCoin"],
    };
    try {
      const transaction = await client.generateTransaction(
        bob.address(),
        payload
      );
      const signature = await client.signTransaction(bob, transaction);
      const tx = await client.submitTransaction(signature);
      await client.waitForTransaction(tx.hash, { checkSuccess: true });
      const resource = await client.getAccountResource(
        alice.address(),
        `${moduleOwner.address()}::Auction::AuctionItem<0x1::aptos_coin::AptosCoin>`
      );
      const aliceData: Table = resource.data;
      const handle = aliceData.items?.handle;
      const tokenDataId: TokenDataId = {
        creator: alice.address().toShortString(),
        collection: aliceCollection.name,
        name: aliceTokens[0].name,
      };
      const key: TokenId = {
        token_data_id: tokenDataId,
        property_version: "0",
      };
      if (handle != null) {
        const item: AuctionItem = await client.getTableItem(handle, {
          key: key,
          key_type: "0x3::token::TokenId",
          value_type: `${moduleOwner.address()}::Auction::Item<0x1::aptos_coin::AptosCoin>`,
        });
        expect(Number(item.current_bid?.value)).toBe(101);
      }
      else {
        throw "Resource does not exist";
      }
    } catch (error) {
      console.log(error);
      throw error;
    }
  });

  it("can purchase after the auction is over", async () => {
    // await sleep(4000);
    const data = [
      alice.address(),
      alice.address(),
      aliceCollection.name,
      aliceTokens[0].name,
      0,
    ];
    const payload = {
      arguments: data,
      function: `${moduleOwner.address()}::Auction::close_and_transfer`,
      type: "entry_function_payload",
      type_arguments: ["0x1::aptos_coin::AptosCoin"],
    };
    try {
      const transaction = await client.generateTransaction(
        bob.address(),
        payload
      );
      const signature = await client.signTransaction(bob, transaction);
      const tx = await client.submitTransaction(signature);
      await client.waitForTransaction(tx.hash, { checkSuccess: true });
      const tokenId = {
        token_data_id: {
          creator: alice.address().hex(),
          collection: aliceCollection.name,
          name: aliceTokens[0].name,
        },
        property_version: `0`,
      };
      const bobTokenBalance = await tokenClient.getTokenForAccount(
        bob.address(),
        tokenId
      );
      expect(Number(bobTokenBalance.amount)).toBe(1);
    } catch (error) {
      console.log(error);
      throw error;
    }
  });
});

describe("Fixed Price Transaction", () => {
  it("can initialize listing", async () => {
    // For a custom transaction, pass the function name with deployed address
    // syntax: deployed_address::module_name::struct_name
    const data = [
      alice.address(),
      aliceCollection.name,
      aliceTokens[1].name,
      100,
      8000000,
      0,
    ];
    const payload = {
      arguments: data,
      function: `${moduleOwner.address()}::FixedPriceSale::list_token`,
      type: "entry_function_payload",
      type_arguments: ["0x1::aptos_coin::AptosCoin"],
    };
    try {
      const transaction = await client.generateTransaction(
        alice.address(),
        payload
      );
      const signature = await client.signTransaction(alice, transaction);
      const tx = await client.submitTransaction(signature);
      await client.waitForTransaction(tx.hash, { checkSuccess: true });
      const resource = await client.getAccountResource(
        alice.address(),
        `${moduleOwner.address()}::FixedPriceSale::ListingItem<0x1::aptos_coin::AptosCoin>`
      );
      const aliceData: Table = resource.data;
      const handle = aliceData.items?.handle;

      const tokenDataId: TokenDataId = {
        creator: alice.address().toShortString(),
        collection: aliceCollection.name,
        name: aliceTokens[1].name,
      };

      const key: TokenId = {
        token_data_id: tokenDataId,
        property_version: "0",
      };

      if (handle != null) {
        const item: ListingItem = await client.getTableItem(handle, {
          key: key,
          key_type: "0x3::token::TokenId",
          value_type: `${moduleOwner.address()}::FixedPriceSale::Item<0x1::aptos_coin::AptosCoin>`,
        });
        expect(Number(item.list_price)).toBe(100);
      }
      else {
        throw "Resource does not exist";
      }
    } catch (error) {
      throw error;
    }
  });

  it("can purchase the listed token", async () => {
    // await sleep(4000);
    const data = [
      alice.address(),
      alice.address(),
      aliceCollection.name,
      aliceTokens[1].name,
      0,
    ];
    const payload = {
      arguments: data,
      function: `${moduleOwner.address()}::FixedPriceSale::buy_token`,
      type: "entry_function_payload",
      type_arguments: ["0x1::aptos_coin::AptosCoin"],
    };
    try {
      const transaction = await client.generateTransaction(
        bob.address(),
        payload
      );
      const signature = await client.signTransaction(bob, transaction);
      const tx = await client.submitTransaction(signature);
      await client.waitForTransaction(tx.hash, { checkSuccess: true });
      const tokenId = {
        token_data_id: {
          creator: alice.address().hex(),
          collection: aliceCollection.name,
          name: aliceTokens[1].name,
        },
        property_version: `0`,
      };
      const bobTokenBalance = await tokenClient.getTokenForAccount(
        bob.address(),
        tokenId
      );
      expect(Number(bobTokenBalance.amount)).toBe(1);
    } catch (error) {
      console.log(error);
      throw error;
    }
  });
});
