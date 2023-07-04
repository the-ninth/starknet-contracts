use starknet::ContractAddress;

#[starknet::interface]
trait IRandomProducer<TContractState> {
    fn request_random(ref self: TContractState) -> u128;
    fn fulfill(ref self: TContractState, request_id: u128, randomness: felt252);
}

#[starknet::interface]
trait IRandomConsumer<TContractState> {
    fn fulfillRandomness(ref self: TContractState, request_id: u128, randomness: felt252);
}
