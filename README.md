# move-nft-framework

This is an escrowless Auction house module.

- Seller can list their NFT by specifying the minimum bid price and give the the contract the permission to transfer the token when the auction is closed.
- Users can bid on the NFT as long as the auction is active.
- The previous bid is transfered back the previous bidder when a higher bid is taken place.
- Once the auction is closed, the seller or the buyer can call the contract and receive the token and coins respectively. Either seller or buyer can call 
the `close_and_transfer` function.
