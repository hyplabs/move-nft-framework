module AuctionHouse::Auction {

    use std::signer;
    use std::string;

    use aptos_token::token;
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    const EITEM_ALREADY_EXISTS: u64 = 0;
    const EAUCTION_ITEM_NOT_CREATED: u64 = 1;

    struct AuctionItem<phantom CoinType> has key {
        min_selling_price: u64,
        end_time: u64,
        start_time: u64,
        current_bid: coin::Coin<CoinType>,
        current_bidder: address,
        token: token::TokenId 
    }

    public entry fun initialize_auction<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, min_selling_price: u64, duration: u64, property_version: u64) {

        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);

        assert!(!exists<AuctionItem<CoinType>>(sender_addr), EITEM_ALREADY_EXISTS);

        let start_time = timestamp::now_microseconds();
        let end_time = duration + start_time;

        // Creating a Coin<CoinType> with zero value which would be increased when someone bids
        let zero_coin = coin::zero<CoinType>();

        move_to<AuctionItem<CoinType>>(sender, 
            AuctionItem{
                min_selling_price, 
                end_time, 
                start_time, 
                current_bid: zero_coin, 
                current_bidder: sender_addr, 
                token: token_id
                }
        );
    }

    #[test_only]
    struct FakeCoin{}

    #[test(module_owner = @AuctionHouse, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    public fun can_initialize_auction(seller: signer, aptos_framework: signer) {

        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let collection_name = b"abc";
        let token_name = b"xyz";
        let min_selling_price = 100;
        let duration = 60 * 60 * 24 * 1000000; // duration for 1 day in microseconds
        let property_version = 1;

        let seller_addr = signer::address_of(&seller);

        initialize_auction<FakeCoin>(&seller, seller_addr, collection_name, token_name, min_selling_price, duration, property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 

        
    }

}