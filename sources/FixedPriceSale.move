module Marketplace::FixedPriceSale {

    use std::signer;
    use std::string;

    use aptos_token::token;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_account;

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
        - Hashmaps to store multiple NFT
        - Different tests
        - cancel listing
        - emit events
        - single function to create collection and NFT
        - Typescript tests
    */

    struct ListingItem<phantom CoinType> has key {
        list_price: u64,
        end_time: u64,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability
    }

    public entry fun list_token<CoinType>(sender: &signer, creator: address, collection_name: vector<u8>, token_name: vector<u8>, list_price: u64, expiration_time: u64, property_version: u64) {

        let sender_addr = signer::address_of(sender);
        let token_id = token::create_token_id_raw(creator, string::utf8(collection_name), string::utf8(token_name), property_version);

        assert!(!exists<ListingItem<CoinType>>(sender_addr), EITEM_ALREADY_EXISTS);
        // Check if the seller actually owns the NFT
        assert!(token::balance_of(sender_addr, token_id) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let start_time = timestamp::now_microseconds();
        let end_time = expiration_time + start_time;

        let withdrawCapability = token::create_withdraw_capability(sender, token_id, 1, expiration_time);

        move_to<ListingItem<CoinType>>(sender, 
            ListingItem{
                list_price, 
                end_time, 
                token: token_id,
                withdrawCapability
                }
        );
    }

    public entry fun buy_token<CoinType>(buyer: &signer, seller: address, _creator: address, _collection_name: vector<u8>, _token_name: vector<u8>, _property_version: u64) acquires ListingItem {

        assert!(exists<ListingItem<CoinType>>(seller), EAUCTION_ITEM_DOES_NOT_EXIST);

        let buyer_addr = signer::address_of(buyer);
        let listing_item = borrow_global_mut<ListingItem<CoinType>>(seller);

        let current_time = timestamp::now_microseconds();
        assert!(current_time < listing_item.end_time, ELISTING_IS_CLOSED);

        // Check if the seller still owns the token
        assert!(token::balance_of(seller, listing_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);  
        assert!(coin::balance<CoinType>(buyer_addr) > listing_item.list_price, EINSUFFICIENT_BALANCE);

        token::opt_in_direct_transfer(buyer, true);


        let list = move_from<ListingItem<CoinType>>(seller);

        let ListingItem<CoinType> {
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

    }

    public fun cancel_listing<CoinType>(seller: &signer, _creator: address, _collection_name: vector<u8>, _token_name: vector<u8>, _property_version: u64) acquires ListingItem {
        let seller_addr = signer::address_of(seller);
        assert!(exists<ListingItem<CoinType>>(seller_addr), EAUCTION_ITEM_DOES_NOT_EXIST);

        let listing_item = borrow_global_mut<ListingItem<CoinType>>(seller_addr);
        assert!(token::balance_of(seller_addr, listing_item.token) > 0, ESELLER_DOESNT_OWN_TOKEN);

        let list = move_from<ListingItem<CoinType>>(seller_addr);

        let ListingItem<CoinType> {
            list_price: _,
            end_time: _,
            token: _,
            withdrawCapability: _
        } = list;
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
    #[expected_failure(abort_code = 4)]
    public fun cancel_after_sold_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem {
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
        assert!(!exists<ListingItem<FakeCoin>>(seller_addr), ERESOURCE_NOT_DESTROYED);
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (constants.initial_mint_amount - constants.list_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(seller_addr) == (constants.initial_mint_amount + constants.list_price), EINVALID_BALANCE);

        cancel_listing<FakeCoin>(&seller, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 4)]
    public fun buy_after_canceled_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem {
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
        assert!(!exists<ListingItem<FakeCoin>>(seller_addr), ERESOURCE_NOT_DESTROYED); 

        // The user cannot buy the token since the listing has been canceled
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    }

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    #[expected_failure(abort_code = 5)]
    public fun buy_after_expiration_fail(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem {
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

        // The buying would fail since the time has expired
        timestamp::fast_forward_seconds(constants.expiration_time);
        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, constants.collection_name, constants.token_name, constants.property_version);
    } 
}