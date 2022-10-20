module Marketplace::FixedPriceSale {

    use std::signer;
    use std::string;

    use aptos_token::token;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use aptos_framework::managed_coin;
    use aptos_framework::aptos_account;

    struct AuctionItem<phantom CoinType> has key {
        list_price: u64,
        end_time: u64,
        start_time: u64,
        current_bidder: address,
        token: token::TokenId,
        withdrawCapability: token::WithdrawCapability
    }
}