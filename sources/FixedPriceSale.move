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

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    public fun end_to_end(seller: signer, buyer: signer, module_owner: signer, aptos_framework: signer) acquires ListingItem {
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        let collection_name = b"abc";
        let token_name = b"xyz";
        let list_price = 100;
        let expiration_time = 60 * 60 * 24 * 1000000; // duration for 1 day in microseconds
        let property_version = 0;
        let description = b"This is a token";
        let uri = b"https://example.com";
        let maximum = 10;

        let initial_mint_amount = 10000;

        let seller_addr = signer::address_of(&seller);
        let buyer_addr = signer::address_of(&buyer);


        initialize_coin_and_mint(&module_owner, &seller, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == initial_mint_amount, EINVALID_BALANCE);

        mint(&module_owner, &buyer, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(buyer_addr) == initial_mint_amount, EINVALID_BALANCE);

        // mint a token
        token::create_collection_script(&seller, string::utf8(collection_name), string::utf8(description), string::utf8(uri), maximum, vector<bool>[false, false, false]);
        token::create_token_script(&seller, string::utf8(collection_name), string::utf8(token_name), string::utf8(description), 1, 1, string::utf8(uri), seller_addr, 100, 10, vector<bool>[false, false, false, false, false], vector<string::String>[], vector<vector<u8>>[],vector<string::String>[]);

        list_token<FakeCoin>(&seller, seller_addr, collection_name, token_name, list_price,expiration_time, property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);

        buy_token<FakeCoin>(&buyer, seller_addr, seller_addr, collection_name, token_name, property_version);
        let token = token::create_token_id_raw(seller_addr, string::utf8(collection_name), string::utf8(token_name), property_version); 
        assert!(!exists<ListingItem<FakeCoin>>(seller_addr), ERESOURCE_NOT_DESTROYED);
        assert!(token::balance_of(seller_addr, token) == 0, ESELLER_STILL_OWNS_TOKEN);
        assert!(token::balance_of(buyer_addr, token) == 1, EBUYER_DOESNT_OWN_TOKEN);
        assert!(coin::balance<FakeCoin>(buyer_addr) == (initial_mint_amount - list_price), EINVALID_BALANCE);
        assert!(coin::balance<FakeCoin>(seller_addr) == (initial_mint_amount + list_price), EINVALID_BALANCE);


    } 
}