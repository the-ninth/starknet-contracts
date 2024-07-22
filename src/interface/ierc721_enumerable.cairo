use starknet::ContractAddress;

pub const IERC721_ENUMERABLE_ID: felt252 = 0x16bc0f502eeaf65ce0b3acb5eea656e2f26979ce6750e8502a82f377e538c87;

#[starknet::interface]
pub trait IERC721Enumerable<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
    fn token_by_index(self: @TContractState, index: u256) -> u256;
    fn token_of_owner_by_index(self: @TContractState, owner: ContractAddress, index: u256) -> u256;
}

#[starknet::interface]
pub trait IERC721EnumerableCamel<TContractState> {
    fn totalSupply(self: @TContractState) -> u256;
    fn tokenByIndex(self: @TContractState, index: u256) -> u256;
    fn tokenOfOwnerByIndex(self: @TContractState, owner: ContractAddress, index: u256) -> u256;
}
