use starknet::ContractAddress;

#[starknet::interface]
trait IMintable<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
}