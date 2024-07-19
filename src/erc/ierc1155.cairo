pub const IERC1155Id: u32 = 0xd9b67a26;
pub const IERC1155TokenReceiverId: u32 = 0x4e2312e0;
pub const IERC1155MetadataURIId: u32 = 0x0e89341c;
pub const IERC1155ReceivedSelector: u32 = 0xf23a6e61;
pub const IERC1155BatchReceivedSelector: u32 = 0xbc197c81;

use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC1155<TContractState> {
    fn balanceOf(self: @TContractState, account: ContractAddress, id: u256) -> u256;
    fn balanceOfBatch(self: @TContractState, accounts: Span<ContractAddress>, ids: Span<u256>) -> Span<u256>;
    fn isApprovedForAll(self: @TContractState, owner: ContractAddress, operator: ContractAddress) -> bool;

    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn safeTransferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, id: u256, value: u256, data: Span<felt252>);
    fn safeBatchTransferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>);
}

#[starknet::interface]
pub trait IERC1155MetadataURI<TContractState> {
    fn uri(self: @TContractState, id: u256) -> Span<felt252>;
}

#[starknet::interface]
pub trait IERC1155TokenReceiver<TContractState> {
    fn onERC1155Received(ref self: TContractState, operator: ContractAddress, from: ContractAddress, id: u256, value: u256, data: Span<felt252>) -> u32;
    fn onERC1155BatchReceived(ref self: TContractState, operator: ContractAddress, from: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>) -> u32;
}


