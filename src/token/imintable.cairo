use starknet::ContractAddress;

#[starknet::interface]
pub trait IMintable<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}