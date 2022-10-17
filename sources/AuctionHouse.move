module AuctionHouse::Auction {

    use std::signer;
    use std::string;

    use aptos_token::token;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_account;

    const EITEM_ALREADY_EXISTS: u64 = 0;
    const EAUCTION_ITEM_NOT_CREATED: u64 = 1;
    const EAUCTION_HAS_ENDED: u64 = 2;
    const EBID_AMOUNT_IS_LOW: u64 = 3;
    const ESELLER_DOESNT_OWN_TOKEN: u64 = 4;
    const EINSUFFICIENT_BALANCE: u64 = 5;
    const EINVALID_BALANCE: u64 = 6;
    const EAUCTION_IS_STILL_GOING_ON: u64 = 7;
    const ENOBODY_HAS_BID: u64 = 8;
    const ESELLER_STILL_OWNS_TOKEN: u64 = 9;
    const EBUYER_DOESNT_OWN_TOKEN: u64 = 10;
    const ERESOURCE_NOT_REMOVED: u64 = 11;

    struct AuctionItem<phantom CoinType> has key {
        min_selling_price: u64,
        end_time: u64,
        start_time: u64,
        current_bid: coin::Coin<CoinType>,
        current_bidder: address,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability
    }

    public entry fun initialize_auction<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, min_selling_price: u64, duration: u64, property_version: u64) {

        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);

        assert!(!exists<AuctionItem<CoinType>>(sender_addr), EITEM_ALREADY_EXISTS);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(sender_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = duration + start_time;

        // Creating a Coin<CoinType> with zero value which would be increased when someone bids
        let zero_coin = coin::zero<CoinType>();

        let withdrawCapability = token::create_withdraw_capability(sender, token_id, 1, 100000000);

        move_to<AuctionItem<CoinType>>(sender, 
            AuctionItem{
                min_selling_price, 
                end_time, 
                start_time, 
                current_bid: zero_coin, 
                current_bidder: sender_addr, 
                token: token_id,
                withdrawCapability
                }
        );
    }

    public entry fun bid<CoinType>(bidder: &signer, seller: address, _creator: address, _collection_name: vector<u8>, _token_name: vector<u8>, _property_version: u64, bid_amount: u64) acquires AuctionItem {

        assert!(exists<AuctionItem<CoinType>>(seller), EAUCTION_ITEM_NOT_CREATED);

        let bidder_addr = signer::address_of(bidder);

        let auction_item = borrow_global_mut<AuctionItem<CoinType>>(seller);
        let current_time = timestamp::now_microseconds();

        let current_bid = coin::value(&mut auction_item.current_bid);
        if (current_bid == 0) {
            current_bid = auction_item.min_selling_price;
        };

        assert!(current_time < auction_item.end_time, EAUCTION_HAS_ENDED);
        assert!(bid_amount > current_bid, EBID_AMOUNT_IS_LOW);
        assert!(coin::balance<CoinType>(bidder_addr) > bid_amount, EINSUFFICIENT_BALANCE);

        // Check if the seller still owns the token
        assert!(token::balance_of(seller, auction_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN); 

        // give back the exisiting bid to previous bidder
        let existing_coins = coin::extract_all<CoinType>(&mut auction_item.current_bid);
        coin::deposit<CoinType>(auction_item.current_bidder, existing_coins);

        let bid = coin::withdraw<CoinType>(bidder, bid_amount);
        coin::merge<CoinType>(&mut auction_item.current_bid, bid); 
        auction_item.current_bidder = bidder_addr;

        // The user should opt in direct transfer to claim token
        // TODO: opt in only for particular token id
        token::opt_in_direct_transfer(bidder, true);


    }

    public entry fun close_and_transfer<CoinType>(seller_or_buyer: &signer, seller: address, _creator: address, _collection_name: vector<u8>, _token_name: vector<u8>, _property_version: u64) acquires AuctionItem {
        assert!(exists<AuctionItem<CoinType>>(seller), EAUCTION_ITEM_NOT_CREATED);

        let auction_item = borrow_global_mut<AuctionItem<CoinType>>(seller);

        let current_time = timestamp::now_microseconds();
        assert!(current_time > auction_item.end_time, EAUCTION_IS_STILL_GOING_ON);
        assert!(seller != auction_item.current_bidder, ENOBODY_HAS_BID);
        assert!(token::balance_of(seller, auction_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);  

        // The bid amount is transfered to the seller
        let bid_amount = coin::extract_all<CoinType>(&mut auction_item.current_bid);
        coin::deposit<CoinType>(seller, bid_amount);

        let auc = move_from<AuctionItem<CoinType>>(seller);

        let AuctionItem<CoinType> {
            min_selling_price: _,
            end_time: _,
            start_time: _,
            current_bid,
            current_bidder: _,
            token: _,
            withdrawCapability: withdrawCapability,
            } = auc;
        coin::destroy_zero<CoinType>(current_bid);

        // Since withdrawCapability doesnt have copy ability, the item has to be destructured and then be used
        // So now the token is been transfered to the buyer without the seller needing the sign
        let token = token::withdraw_with_capability(withdrawCapability);
        token::direct_deposit_with_opt_in(signer::address_of(seller_or_buyer), token);
        
    }

    #[test_only]
    struct FakeCoin{}

    #[test_only]
    public fun initialize_coin_and_mint(admin: &signer, user: &signer, mint_amount: u64) {
        let user_addr = signer::address_of(user);
        managed_coin::initialize<FakeCoin>(admin, b"fake", b"F", 9, false);
        aptos_account::create_account(user_addr);
        managed_coin::register<FakeCoin>(user);
        managed_coin::mint<FakeCoin>(admin, user_addr, mint_amount); 
    }

    #[test(module_owner = @AuctionHouse, seller = @0x4, buyer= @0x5,  aptos_framework = @0x1)]
    // #[expected_failure(abort_code = 3)]
    public fun can_initialize_auction(seller: signer, aptos_framework: signer, buyer: signer, module_owner: signer) acquires AuctionItem {

        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let collection_name = b"abc";
        let token_name = b"xyz";
        let min_selling_price = 100;
        let duration = 60 * 60 * 24 * 1000000; // duration for 1 day in microseconds
        let property_version = 0;
        let description = b"This is a token";
        let uri = b"https://example.com";
        let maximum = 10;

        let initial_mint_amount = 10000;

        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &buyer, initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        
        // mint a token
        token::create_collection_script(&seller, string::utf8(collection_name), string::utf8(description), string::utf8(uri), maximum, vector<bool>[false, false, false]);
        token::create_token_script(&seller, string::utf8(collection_name), string::utf8(token_name), string::utf8(description), 1, 1, string::utf8(uri), seller_addr, 100, 10, vector<bool>[false, false, false, false, false], vector<string::String>[], vector<vector<u8>>[],vector<string::String>[]);

        initialize_auction<FakeCoin>(&seller, seller_addr, collection_name, token_name, min_selling_price, duration, property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 

        let first_bid_amount = 900;

        bid<FakeCoin>(&buyer, seller_addr, seller_addr, collection_name, token_name, property_version, first_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (initial_mint_amount - first_bid_amount), EINVALID_BALANCE);

        timestamp::fast_forward_seconds(duration/1000);

        close_and_transfer<FakeCoin>(&buyer, seller_addr, seller_addr, collection_name, token_name, property_version); 
        assert!(coin::balance<FakeCoin>(seller_addr) == (first_bid_amount), EINVALID_BALANCE);
        let token = token::create_token_id_raw(seller_addr, string::utf8(collection_name), string::utf8(token_name), property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);  
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);  
        assert!(!exists<AuctionItem<FakeCoin>>(seller_addr), ERESOURCE_NOT_REMOVED) 

    }

}