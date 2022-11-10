module Marketplace::FixedPriceSale {

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
    const ESELLER_DOESNT_OWN_TOKEN: u64 = 1;
    const EINVALID_BALANCE: u64 = 2;
    const EITEM_NOT_LISTED: u64 = 3;
    const EAUCTION_ITEM_DOES_NOT_EXIST: u64 = 4;
    const ELISTING_IS_CLOSED: u64 = 5;
    const EINSUFFICIENT_BALANCE: u64 = 6;
    const ERESOURCE_NOT_DESTROYED: u64 = 7;
    const ESELLER_STILL_OWNS_TOKEN: u64 = 8;
    const EBUYER_DOESNT_OWN_TOKEN: u64 = 9;

    /*
        TODO:
        - ~~Hashmaps to store multiple NFT~~
        - ~~Different tests~~
        - ~~cancel listing~~
        - ~~emit events~~
        - ~~single function to create collection and NFT~~
        - ~~Typescript tests~~
    */

    struct Item<phantom CoinType> has store {
        list_price: u64,
        end_time: u64,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability
    }

    struct CreateListingEvent has store, drop {
        listing_price: u64,
        end_time: u64,
        start_time: u64,
        seller: address,
        token: token::TokenId
    }

    struct CancelEvent has store, drop {
        listing_price: u64,
        cancel_time: u64,
        seller: address,
        token: token::TokenId,
    }

    struct BuyEvent has store, drop {
        buy_price: u64,
        buy_time: u64,
        buyer: address,
        seller: address,
        token: token::TokenId,
    }

    struct ListingItem<phantom CoinType> has key {
        items: Table<token::TokenId, Item<CoinType>> 
    }

    struct ListingEvents has key {
        create_listing: event::EventHandle<CreateListingEvent>,
        cancel_listing: event::EventHandle<CancelEvent>,
        complete_listing: event::EventHandle<BuyEvent>,
    }

    public entry fun list_token<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, list_price: u64, expiration_time: u64, property_version: u64) acquires ListingItem, ListingEvents {

        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);

        assert!(!exists<ListingItem<CoinType>>(sender_addr), EITEM_ALREADY_EXISTS);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(sender_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = expiration_time + start_time;

        let withdrawCapability = token::create_withdraw_capability(sender, token_id, 1, end_time);
        let item = Item {
                list_price, 
                end_time, 
                token: token_id,
                withdrawCapability
        };
        if (exists<ListingItem<CoinType>>(sender_addr)) {
            let list_items = borrow_global_mut<ListingItem<CoinType>>(sender_addr);
            table::add(&mut list_items.items, token_id, item);
        } else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<ListingItem<CoinType>>(sender, 
             ListingItem {items: new_item }
            );
        };
        let create_listing_event = CreateListingEvent {
            listing_price: list_price,
            end_time,
            start_time,
            seller: sender_addr,
            token: token_id 
        };
        if (exists<ListingEvents>(sender_addr)) {
            let auction_events = borrow_global_mut<ListingEvents>(sender_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        }
        else {
            move_to<ListingEvents>(sender, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(sender),
                cancel_listing: account::new_event_handle<CancelEvent>(sender),
                complete_listing: account::new_event_handle<BuyEvent>(sender)
            });
            let auction_events = borrow_global_mut<ListingEvents>(sender_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event, 
           );
        }
    }

    public entry fun create_collection_token_and_list<CoinType>(
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
        list_price: u64, 
        expiration_time: u64, 
    ) acquires ListingItem, ListingEvents {
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
        assert!(!exists<ListingItem<CoinType>>(creator_addr), EITEM_ALREADY_EXISTS);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(creator_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = expiration_time + start_time;

        let withdrawCapability = token::create_withdraw_capability(creator, token_id, 1, expiration_time);

        let item = Item {
                list_price, 
                end_time, 
                token: token_id,
                withdrawCapability
        };
        if (exists<ListingItem<CoinType>>(creator_addr)) {
            let list_items = borrow_global_mut<ListingItem<CoinType>>(creator_addr);
            table::add(&mut list_items.items, token_id, item);
        } else {
            let new_item = table::new();
            table::add(&mut new_item, token_id, item);
            move_to<ListingItem<CoinType>>(creator, 
             ListingItem {items: new_item }
            );
        };
        let create_listing_event = CreateListingEvent {
            listing_price: list_price,
            end_time,
            start_time,
            seller: creator_addr,
            token: token_id 
        };
        if (exists<ListingEvents>(creator_addr)) {
            let auction_events = borrow_global_mut<ListingEvents>(creator_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event,
            );
        }
        else {
            move_to<ListingEvents>(creator, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(creator),
                cancel_listing: account::new_event_handle<CancelEvent>(creator),
                complete_listing: account::new_event_handle<BuyEvent>(creator)
            });
            let auction_events = borrow_global_mut<ListingEvents>(creator_addr);
            event::emit_event<CreateListingEvent>(
                &mut auction_events.create_listing,
                create_listing_event, 
           );
        }
    }

    public entry fun buy_token<CoinType>(buyer: &signer, seller: address, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires ListingItem, ListingEvents {

        assert!(exists<ListingItem<CoinType>>(seller), EAUCTION_ITEM_DOES_NOT_EXIST);

        let buyer_addr = signer::address_of(buyer);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let listing_items = borrow_global_mut<ListingItem<CoinType>>(seller);
        let listing_item = table::borrow_mut(&mut listing_items.items, token_id);

        let current_time = timestamp::now_microseconds();
        assert!(current_time < listing_item.end_time, ELISTING_IS_CLOSED);

        // Check if the seller still owns the token
        assert!(token::balance_of(seller, listing_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);  
        assert!(coin::balance<CoinType>(buyer_addr) > listing_item.list_price, EINSUFFICIENT_BALANCE);

        token::opt_in_direct_transfer(buyer, true);


        let list = table::remove(&mut listing_items.items, token_id);

        let Item<CoinType> {
            list_price: price,
            end_time: _,
            token: _,
            withdrawCapability: withdrawCapability,
            } = list;

        coin::transfer<CoinType>(buyer, seller, price); 
        // Since withdrawCapability doesnt have copy ability, the item has to be destructured and then be used
        // So now the token is been transfered to the buyer without the seller needing the sign
        let token = token::withdraw_with_capability(withdrawCapability);
        token::direct_deposit_with_opt_in(buyer_addr, token);
        let complete_listing_event = BuyEvent {
            buy_price: price,
            buy_time: current_time,
            buyer: buyer_addr,
            seller,
            token: token_id 
        };
        if (exists<ListingEvents>(buyer_addr)) {
            let auction_events = borrow_global_mut<ListingEvents>(buyer_addr);
            event::emit_event<BuyEvent>(
                &mut auction_events.complete_listing,
                complete_listing_event,
            );
        }
        else {
            move_to<ListingEvents>(buyer, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(buyer),
                cancel_listing: account::new_event_handle<CancelEvent>(buyer),
                complete_listing: account::new_event_handle<BuyEvent>(buyer)
            });
            let auction_events = borrow_global_mut<ListingEvents>(buyer_addr);
            event::emit_event<BuyEvent>(
                &mut auction_events.complete_listing,
                complete_listing_event, 
           );
        }
    }

    public fun cancel_listing<CoinType>(seller: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, property_version: u64) acquires ListingItem, ListingEvents{
        let seller_addr = signer::address_of(seller);
        assert!(exists<ListingItem<CoinType>>(seller_addr), EAUCTION_ITEM_DOES_NOT_EXIST);

        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);
        let listing_items = borrow_global_mut<ListingItem<CoinType>>(seller_addr);
        let listing_item = table::borrow_mut(&mut listing_items.items, token_id);
        assert!(token::balance_of(seller_addr, listing_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let list = table::remove(&mut listing_items.items, token_id);

        let Item<CoinType> {
            list_price: price,
            end_time: _,
            token: _,
            withdrawCapability: _
        } = list;

        let cancel_listing_event = CancelEvent {
            listing_price: price,
            cancel_time: timestamp::now_microseconds(),
            seller: seller_addr,
            token: token_id 
        };
        if (exists<ListingEvents>(seller_addr)) {
            let auction_events = borrow_global_mut<ListingEvents>(seller_addr);
            event::emit_event<CancelEvent>(
                &mut auction_events.cancel_listing,
                cancel_listing_event,
            );
        }
        else {
            move_to<ListingEvents>(seller, ListingEvents{
                create_listing: account::new_event_handle<CreateListingEvent>(seller),
                cancel_listing: account::new_event_handle<CancelEvent>(seller),
                complete_listing: account::new_event_handle<BuyEvent>(seller)
            });
            let auction_events = borrow_global_mut<ListingEvents>(seller_addr);
            event::emit_event<CancelEvent>(
                &mut auction_events.cancel_listing,
                cancel_listing_event, 
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
        list_price: u64,
        expiration_time: u64,
        property_version: u64,
        description: vector<u8>,
        uri: vector<u8>,
        maximum: u64,
        initial_mint_amount: u64,
    }

    #[test_only]
    public fun get_constants() :Constant {
        let constants = Constant {
            collection_name: b"abc",
            token_name: b"xyz",
            list_price: 100,
            expiration_time: 60 * 60 * 24 * 1000000 ,// duration for 1 day in microseconds
            property_version: 0,
            description: b"This is a token",
            uri: b"https://example.com",
            maximum: 10,
            initial_mint_amount: 10000,
        };
        return constants
    }

    #[test_only]
    public fun create_collection_and_token(creator: &signer, constants: &Constant) {
        let creator_addr = signer::address_of(creator);
        token::create_collection_script(creator, string::utf8(constants.collection_name), string::utf8(constants.description), string::utf8(constants.uri), constants.maximum, vector<bool>[false, false, false]);
        token::create_token_script(creator, string::utf8(constants.collection_name), string::utf8(constants.token_name), string::utf8(constants.description), 1, 1, string::utf8(constants.uri), creator_addr, 100, 10, vector<bool>[false, false, false, false, false], vector<string::String>[], vector<vector<u8>>[],vector<string::String>[]);
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    public fun end_to_end_with_seller_already_owning_token(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        // mint a token
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.list_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.initial_mint_amount + constants.list_price), EINVALID_BALANCE);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    public fun end_to_end_with_creator_minting_token(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        create_collection_token_and_list<FakeCoin>(
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
            constants.list_price,
            constants.expiration_time
        ); 
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.list_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.initial_mint_amount + constants.list_price), EINVALID_BALANCE);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 25863)]
    public fun cancel_after_sold_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        // mint a token
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.list_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.initial_mint_amount + constants.list_price), EINVALID_BALANCE);

        cancel_listing<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 25863)]
    public fun buy_after_canceled_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        // mint a token
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED); 
        cancel_listing<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
        // The user cannot buy the token since the listing has been canceled
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 5)]
    public fun buy_after_expiration_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);
        // The buying would fail since the time has expired
        timestamp::fast_forward_seconds(constants.expiration_time);
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 1)]
    public fun buy_when_user_doesnt_own_token_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);
        let module_owner_addr = signer::address_of(&module_owner);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);

        let token = token::create_token_id_raw(seller_addr, string::utf8(constants.collection_name), string::utf8(constants.token_name), constants.property_version); 
        aptos_account::create_account(module_owner_addr);
        token::opt_in_direct_transfer(&module_owner, true);
        token::transfer(&seller, token, module_owner_addr, 1);
        // The seller does not own token, so the method would fail
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 6)]
    public fun buy_with_insufficient_balance_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem, ListingEvents {
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let constants = get_constants();
        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);

        initialize_coin_and_mint(&module_owner, &seller, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        mint(&module_owner, &buyer, constants.initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == constants.initial_mint_amount, EINVALID_BALANCE);
        create_collection_and_token(&seller, &constants);

        list_token<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.list_price , constants.expiration_time, constants.property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);
        coin::transfer<FakeCoin>(&buyer, seller_addr, constants.initial_mint_amount - 10);
        // The buyer does not have sufficient balance to buy the item so the method would fail
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 

}