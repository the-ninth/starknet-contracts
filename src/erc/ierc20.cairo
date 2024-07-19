use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20<TContractState> {
    
    fn name(self: @TContractState) -> felt252;
    
    fn symbol(self: @TContractState) -> felt252;
    
    fn decimals(self: @TContractState) -> u8;
    
    fn totalSupply(self: @TContractState) -> u256;
    
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    
    fn increaseAllowance(ref self: TContractState, spender: ContractAddress, added_value: u256) -> bool;
    
    fn decreaseAllowance(ref self: TContractState, spender: ContractAddress, subtracted_value: u256) -> bool;
}