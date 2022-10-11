module AuctionHouse::Auction {

    use aptos_token::token;
    use aptos_framework::coin;

    struct AuctionItem<CoinStore> has key {
        min_selling_price: u64,
        end_time: u64,
        start_time: u64,
        current_bid: coin::Coin<CoinStore>,
        current_bidder: address,
        token: token::TokenId 
    }

    public entry fun initialize_auction<CoinStore>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, min_selling_price: u64, duration: u64) {

    }

}