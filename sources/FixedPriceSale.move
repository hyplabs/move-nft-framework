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

    struct ListingItem<phantom CoinType> has key {
        list_price: u64,
        end_time: u64,
        start_time: u64,
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
                start_time, 
                token: token_id,
                withdrawCapability
                }
        );
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

    #[test(module_owner = @Marketplace, seller = @0x4, buyer= @0x5, aptos_framework = @0x1)]
    public fun end_to_end(seller: signer, module_owner: signer, aptos_framework: signer) {
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

        initialize_coin_and_mint(&module_owner, &seller, initial_mint_amount);
        assert!(coin::balance<FakeCoin>(seller_addr) == initial_mint_amount, EINVALID_BALANCE);

        // mint a token
        token::create_collection_script(&seller, string::utf8(collection_name), string::utf8(description), string::utf8(uri), maximum, vector<bool>[false, false, false]);
        token::create_token_script(&seller, string::utf8(collection_name), string::utf8(token_name), string::utf8(description), 1, 1, string::utf8(uri), seller_addr, 100, 10, vector<bool>[false, false, false, false, false], vector<string::String>[], vector<vector<u8>>[],vector<string::String>[]);

        list_token<FakeCoin>(&seller, seller_addr, collection_name, token_name, list_price,expiration_time, property_version);
        assert!(exists<ListingItem<FakeCoin>>(seller_addr), EITEM_NOT_LISTED);

    } 
}