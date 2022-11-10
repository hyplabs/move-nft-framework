module Marketplace::Auction {

    use std::signer;
    use std::string;

    use aptos_token::token;

    use aptos_std::table::{Self, Table};

    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_account;
    use aptos_framework::account;
    use aptos_framework::event;

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
    const EINVALID_SIGNER: u64 = 12;

    struct Item<phantom CoinType> has store {
        min_selling_price: u64,
        end_time: u64,
        start_time: u64,
        current_bid: coin::Coin<CoinType>,
        current_bidder: address,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability
    }

    struct CreateAuctionEvent has store, drop {
        min_selling_price: u64,
        end_time: u64,
        start_time: u64,
        seller: address,
        token: token::TokenId
    }

    struct BidEvent has store, drop {
        bid_price: u64,
        bid_time: u64,
        bidder: address,
        token: token::TokenId,
        previous_bid: u64
    }

    struct CompleteAuctionEvent has store, drop {
        buy_price: u64,
        buy_time: u64,
        buyer: address,
        seller: address,
        token: token::TokenId,
    }

    struct AuctionItem<phantom CoinType> has key {
        items: Table<token::TokenId, Item<CoinType>> 
    }

    struct AuctionEvents has key {
        create_auction: event::EventHandle<CreateAuctionEvent>,
        bid: event::EventHandle<BidEvent>,
        complete_auction: event::EventHandle<CompleteAuctionEvent>,
    }

    public entry fun initialize_auction<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, min_selling_price: u64, duration: u64, property_version: u64) acquires AuctionItem, AuctionEvents {

        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(sender_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);
        let start_time = timestamp::now_microseconds();
        let end_time = duration + start_time;
        // Creating a Coin<CoinType> with zero value which would be increased when someone bids
        let zero_coin = coin::zero<CoinType>();
        let withdrawCapability = token::create_withdraw_capability(sender, token_id, 1, end_time + 1000000);
        let item = Item{
                min_selling_price, 
                end_time, 
                start_time, 
                current_bid: zero_coin, 
                current_bidder: sender_addr, 
                token: token_id,
                withdrawCapability
        };
        if (exists<AuctionItem<CoinType>>(sender_addr)) {
            let auction_items = borrow_global_mut<AuctionItem<CoinType>>(sender_addr);
            table::add(&mut auction_items.items, token_id, item);
        } else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<AuctionItem<CoinType>>(sender, 
             AuctionItem {items: new_item }
            );
        };
        let create_auction_event = CreateAuctionEvent {
            min_selling_price,
            end_time,
            start_time,
            seller: sender_addr,
            token: token_id 
        };
        if (exists<AuctionEvents>(sender_addr)) {
            let auction_events = borrow_global_mut<AuctionEvents>(sender_addr);
            event::emit_event<CreateAuctionEvent>(
                &mut auction_events.create_auction,
                create_auction_event,
            );
        }
        else {
            move_to<AuctionEvents>(sender, AuctionEvents{
                create_auction: account::new_event_handle<CreateAuctionEvent>(sender),
                bid: account::new_event_handle<BidEvent>(sender),
                complete_auction: account::new_event_handle<CompleteAuctionEvent>(sender)
            });
            let auction_events = borrow_global_mut<AuctionEvents>(sender_addr);
            event::emit_event<CreateAuctionEvent>(
                &mut auction_events.create_auction,
                create_auction_event, 
           );
        }

    }

    public entry fun create_collection_token_and_initialize_auction<CoinType>(
        creator: &signer,
        collection_name: vector<u8>, 
        collection_description: vector<u8>,
        collection_uri: vector<u8>,
        collection_maximum: u64,
        collection_mutate_setting: vector<bool>,
        token_name: vector<u8>, 
        token_description: vector<u8>,
        token_uri: vector<u8>,
        royalty_payee_address: address,
        royalty_points_denominator: u64,
        royalty_points_numerator: u64,
        token_mutate_setting: vector<bool>,
        property_keys: vector<string::String>,
        property_values: vector<vector<u8>>,
        property_types: vector<string::String>,
        min_selling_price: u64, 
        duration: u64, 
    ) acquires AuctionItem, AuctionEvents {
        let creator_addr = signer::address_of(creator); 
        token::create_collection_script(
            creator, 
            string::utf8(collection_name), 
            string::utf8(collection_description), 
            string::utf8(collection_uri), 
            collection_maximum, 
            collection_mutate_setting
        );
        token::create_token_script(
            creator, 
            string::utf8(collection_name), 
            string::utf8(token_name), 
            string::utf8(token_description), 
            1, 
            1, 
            string::utf8(token_uri), 
            royalty_payee_address, 
            royalty_points_denominator, 
            royalty_points_numerator, 
            token_mutate_setting,
            property_keys, 
            property_values, 
            property_types
        );   
        let token_id = token::create_token_id_raw(creator_addr, string::utf8(collection_name), string::utf8(token_name), 0);
        assert!(!exists<AuctionItem<CoinType>>(creator_addr), EITEM_ALREADY_EXISTS);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(creator_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);
        let start_time = timestamp::now_microseconds();
        let end_time = duration + start_time;
        // Creating a Coin<CoinType> with zero value which would be increased when someone bids
        let zero_coin = coin::zero<CoinType>();
        let withdrawCapability = token::create_withdraw_capability(creator, token_id, 1, 100000000);
        let item = Item{
            min_selling_price, 
            end_time, 
            start_time, 
            current_bid: zero_coin, 
            current_bidder: creator_addr, 
            token: token_id,
            withdrawCapability
        };
        if (exists<AuctionItem<CoinType>>(creator_addr)) {
            let auction_items = borrow_global_mut<AuctionItem<CoinType>>(creator_addr);
            table::add(&mut auction_items.items, token_id, item);
        } else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<AuctionItem<CoinType>>(creator,
             AuctionItem {items: new_item }
            );
        };
        let create_auction_event = CreateAuctionEvent {
            min_selling_price,
            end_time,
            start_time,
            seller: creator_addr,
            token: token_id 
        };
        if (exists<AuctionEvents>(creator_addr)) {
            let auction_events = borrow_global_mut<AuctionEvents>(creator_addr);
            event::emit_event<CreateAuctionEvent>(
                &mut auction_events.create_auction,
                create_auction_event,
            );
        }
        else {
            move_to<AuctionEvents>(creator, AuctionEvents{
                create_auction: account::new_event_handle<CreateAuctionEvent>(creator),
                bid: account::new_event_handle<BidEvent>(creator),
                complete_auction: account::new_event_handle<CompleteAuctionEvent>(creator)
            });
            let auction_events = borrow_global_mut<AuctionEvents>(creator_addr);
            event::emit_event<CreateAuctionEvent>(
                &mut auction_events.create_auction,
                create_auction_event, 
           );
        }
     }



    public entry fun bid<CoinType>(bidder: &signer, seller: address, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64, bid_amount: u64) acquires AuctionItem, AuctionEvents {

        assert!(exists<AuctionItem<CoinType>>(seller), EAUCTION_ITEM_NOT_CREATED);

        let bidder_addr = signer::address_of(bidder);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let auction_items = borrow_global_mut<AuctionItem<CoinType>>(seller);
        let auction_item = table::borrow_mut(&mut auction_items.items, token_id);
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
        let bid_time = timestamp::now_microseconds();
        let bid_event = BidEvent {
            bid_price: bid_amount, 
            bid_time,
            bidder: bidder_addr,
            token: token_id,
            previous_bid: current_bid 
        };
        if (exists<AuctionEvents>(bidder_addr)) {
            let auction_events = borrow_global_mut<AuctionEvents>(bidder_addr);
            event::emit_event<BidEvent>(
                &mut auction_events.bid,
                bid_event,
            );
        }
        else {
            move_to<AuctionEvents>(bidder, AuctionEvents{
                create_auction: account::new_event_handle<CreateAuctionEvent>(bidder),
                bid: account::new_event_handle<BidEvent>(bidder),
                complete_auction: account::new_event_handle<CompleteAuctionEvent>(bidder),
            });
            let auction_events = borrow_global_mut<AuctionEvents>(bidder_addr);
            event::emit_event<BidEvent>(
                &mut auction_events.bid,
                bid_event, 
           );
        }

    }

    public entry fun close_and_transfer<CoinType>(seller_or_buyer: &signer, seller: address, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires AuctionItem, AuctionEvents {

        let signer_addr = signer::address_of(seller_or_buyer);
        assert!(exists<AuctionItem<CoinType>>(seller), EAUCTION_ITEM_NOT_CREATED);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let auction_items = borrow_global_mut<AuctionItem<CoinType>>(seller);
        let auction_item = table::borrow_mut(&mut auction_items.items, token_id);

        if (signer_addr != seller && signer_addr != auction_item.current_bidder) {
            abort EINVALID_SIGNER
        };
        let current_time = timestamp::now_microseconds();
        assert!(current_time > auction_item.end_time, EAUCTION_IS_STILL_GOING_ON);
        assert!(seller != auction_item.current_bidder, ENOBODY_HAS_BID);
        assert!(token::balance_of(seller, auction_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);  

        // The bid amount is transfered to the seller
        let buy_price = coin::value(&mut auction_item.current_bid);
        let bid_amount = coin::extract_all<CoinType>(&mut auction_item.current_bid);
        coin::deposit<CoinType>(seller, bid_amount);

        let auc = table::remove(&mut auction_items.items, token_id); 

        let Item<CoinType> {
            min_selling_price: _,
            end_time: _,
            start_time: _,
            current_bid,
            current_bidder: buyer,
            token: _,
            withdrawCapability: withdrawCapability,
            } = auc;
        coin::destroy_zero<CoinType>(current_bid);

        // Since withdrawCapability doesnt have copy ability, the item has to be destructured and then be used
        // So now the token is been transfered to the buyer without the seller needing the sign
        let token = token::withdraw_with_capability(withdrawCapability);
        token::direct_deposit_with_opt_in(buyer, token);
        let buy_time = timestamp::now_microseconds();
        let buy_event = CompleteAuctionEvent {
            buy_price,
            buy_time,
            buyer,
            seller,
            token: token_id,
        };
        if (exists<AuctionEvents>(signer_addr)) {
            let auction_events = borrow_global_mut<AuctionEvents>(signer_addr);
            event::emit_event<CompleteAuctionEvent>(
                &mut auction_events.complete_auction,
                buy_event,
            );
        }
        else {
            move_to<AuctionEvents>(seller_or_buyer, AuctionEvents{
                create_auction: account::new_event_handle<CreateAuctionEvent>(seller_or_buyer),
                bid: account::new_event_handle<BidEvent>(seller_or_buyer),
                complete_auction: account::new_event_handle<CompleteAuctionEvent>(seller_or_buyer),
            });
            let auction_events = borrow_global_mut<AuctionEvents>(signer_addr);
            event::emit_event<CompleteAuctionEvent>(
                &mut auction_events.complete_auction,
                buy_event, 
           );
        }
        
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

    #[test_only]
    public fun mint(admin: &signer, user: &signer, mint_amount: u64) {
        let user_addr = signer::address_of(user);
        aptos_account::create_account(user_addr);
        managed_coin::register<FakeCoin>(user);
        managed_coin::mint<FakeCoin>(admin, user_addr, mint_amount); 
    }

    #[test_only]
    struct Constant has drop {
        collection_name: vector<u8>,
        token_name: vector<u8>,
        min_selling_price: u64,
        duration: u64,
        property_version: u64,
        description: vector<u8>,
        uri: vector<u8>,
        maximum: u64,
        initial_mint_amount: u64,
        first_bid_amount: u64,
        second_bid_amount: u64
    }

    #[test_only]
    public fun get_constants() :Constant {
        let constants = Constant {
            collection_name: b"abc",
            token_name: b"xyz",
            min_selling_price: 100,
            duration: 60 * 60 * 24 * 1000000 ,// duration for 1 day in microseconds
            property_version: 0,
            description: b"This is a token",
            uri: b"https://example.com",
            maximum: 10,
            initial_mint_amount: 10000,
            first_bid_amount: 900,
            second_bid_amount: 1000
        };
        return constants
    }

    #[test_only]
    public fun create_collection_and_token(creator: &signer, constants: &Constant) {
        let creator_addr = signer::address_of(creator);
        token::create_collection_script(creator, string::utf8(constants.collection_name), string::utf8(constants.description), string::utf8(constants.uri), constants.maximum, vector<bool>[false, false, false]);
        token::create_token_script(creator, string::utf8(constants.collection_name), string::utf8(constants.token_name), string::utf8(constants.description), 1, 1, string::utf8(constants.uri), creator_addr, 100, 10, vector<bool>[false, false, false, false, false], vector<string::String>[], vector<vector<u8>>[],vector<string::String>[]);
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    public fun end_to_end_with_buyer_closing(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem, AuctionEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.second_bid_amount), EINVALID_BALANCE);
        // The previous bidder getting their bid back
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount ), EINVALID_BALANCE);
        timestamp::fast_forward_seconds(constants.duration/1000);
        close_and_transfer<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version); 
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.second_bid_amount), EINVALID_BALANCE);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);  
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);  
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    public fun end_to_end_with_seller_closing(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.second_bid_amount), EINVALID_BALANCE);
        // The previous bidder getting their bid back
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount ), EINVALID_BALANCE);
        timestamp::fast_forward_seconds(constants.duration/1000);
        close_and_transfer<FakeCoin>(&seller, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version); 
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.second_bid_amount), EINVALID_BALANCE);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);  
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);  
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    public fun end_to_end_with_creator_closing(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        create_collection_token_and_initialize_auction<FakeCoin>(
            &seller, 
            constants.collection_name, 
            constants.description,
            constants.uri, 
            1, 
            vector<bool>[false, false, false], 
            constants.token_name, 
            constants.description,
            constants.uri, 
            seller_addr, 
            100, 
            10, 
            vector<bool>[false, false, false, false, false], 
            vector<string::String>[], 
            vector<vector<u8>>[],
            vector<string::String>[],
            constants.min_selling_price,
            constants.duration
        ); 
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.second_bid_amount), EINVALID_BALANCE);
        // The previous bidder getting their bid back
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount ), EINVALID_BALANCE);
        timestamp::fast_forward_seconds(constants.duration/1000);
        close_and_transfer<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version); 
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.second_bid_amount), EINVALID_BALANCE);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);  
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);  
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 4)]
    public fun initialize_auction_without_holding_token_fail(seller: signer, aptos_framework: signer, buyer: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        // mint a token
        create_collection_and_token(&seller, &constants);

        // Since buyer doesnt hold the specified token, the method would fail
        initialize_auction<FakeCoin>(&buyer, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
    }


    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 2)]
    public fun bid_after_auction_closed_fail(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        // Cannot bid after the auction duration is over
        timestamp::fast_forward_seconds(constants.duration);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
    }



    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 12)]
    public fun external_user_closing_auction_fail(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.second_bid_amount), EINVALID_BALANCE);
        // The previous bidder getting their bid back
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount ), EINVALID_BALANCE);
        timestamp::fast_forward_seconds(constants.duration/1000);
        close_and_transfer<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version); 
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 3)]
    public fun bidding_less_than_previous_fail(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount - 100);
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 7)]
    public fun transfering_before_auction_ends_fail(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, constants.initial_mint_amount);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.second_bid_amount), EINVALID_BALANCE);
        // The previous bidder getting their bid back
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount ), EINVALID_BALANCE);
        close_and_transfer<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version); 
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, first_bidder = @0x6, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 5)]
    public fun bidding_with_low_balance_fail(seller: signer, aptos_framework: signer, buyer: signer, first_bidder: signer, module_owner: signer) acquires AuctionItem , AuctionEvents{
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let first_bidder_addr = signer::address_of(&first_bidder);

        initialize_coin_and_mint(&module_owner, &buyer, 10);
        aptos_account::create_account(seller_addr);
        managed_coin::register<FakeCoin>(&seller);
        mint(&module_owner, &first_bidder, constants.initial_mint_amount);
        // mint a token
        create_collection_and_token(&seller, &constants);

        initialize_auction<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.min_selling_price, constants.duration, constants.property_version);
        assert!(exists<AuctionItem<FakeCoin>>(seller_addr), EAUCTION_ITEM_NOT_CREATED); 
        bid<FakeCoin>(&first_bidder, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.first_bid_amount);
        assert!(coin::balance<FakeCoin>(first_bidder_addr) == (constants.initial_mint_amount - constants.first_bid_amount), EINVALID_BALANCE);
        bid<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version, constants.second_bid_amount);
    }
}