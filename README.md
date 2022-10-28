# move-nft-framework

## Escrowless Auction House

- Seller can list their NFT by specifying the minimum bid price and give the the contract the permission to transfer the token when the auction is closed.
- If a user doesnt have a NFT, they can call create a collection and mint a token and have that listed for fixed price sale all in one go by specifying the required details
- Users can bid on the NFT as long as the auction is active.
- The previous bid is transfered back the previous bidder when a higher bid is taken place.
- Once the auction is closed, the seller or the buyer can call the contract and receive the token and coins respectively. Either seller or buyer can call 
the `close_and_transfer` function.

## Escrowless Fixed Price Sale

- Seller can list their NFT by specifying the listing price and give the the contract the permission to transfer the token for limited period of time set by the seller which would be used to transfer to the buyer they pay the listing price.
- If a user doesnt have a NFT, they can call create a collection and mint a token and have that listed for auction all in one go by specifying the required details
- The buyer can call the function and transfer the amount in listing price and once it is succeeded, the NFT would be transfered to the buyer without having the need of the seller's signature.
- If the seller changes their, they can cancel the listing which would destroy the withdrawal permission gained by the contract.

## How to run

Make sure that you have `aptos` cli installed. If not install it from here: https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli/

- Compile the module
```
aptos move compile
```
- Run the test cases
```
aptos move test
```
- Publish the module
```
aptos init
aptos move publish
```
The aptos init creates a new keypair using which the module can be published.
Note: Publishing the module with the current address wont be possible since the auth key is not present. You would have to create a new keypair and then
replace it in move.toml to continue.
