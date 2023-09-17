use starknet::ContractAddress;

const IERC721TokenReceiverId: u32 = 0x150b7a02;
const IERC721Id: u32 = 0x80ac58cd;
const IERC721MetadataId: u32 = 0x5b5e139f;
const IERC721EnumerableId: u32 = 0x780e9d63;

#[starknet::interface]
trait IERC721<TContractState> {
    fn name(self: @TContractState) -> felt252;
    fn symbol(self: @TContractState) -> felt252;
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn ownerOf(self: @TContractState, token_id: u256) -> ContractAddress;
    fn getApproved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn isApprovedForAll(self: @TContractState, owner: ContractAddress, operator: ContractAddress) -> bool;
    fn tokenURI(self: @TContractState, token_id: u256) -> Array<felt252>;
    fn transferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256);
    fn safeTransferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>);
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
}

#[starknet::interface]
trait IERC721Enumerable<TContractState> {
    fn totalSupply(self: @TContractState) -> u256;
    fn tokenByIndex(self: @TContractState, index: u256) -> u256;
    fn tokenOfOwnerByIndex(self: @TContractState, owner: ContractAddress, index: u256) -> u256;
}

#[starknet::interface]
trait IERC721TokenReceiver<TContractState> {
    fn onERC721Received(ref self: TContractState, operator: ContractAddress, from: ContractAddress, token_id: u256, data: Span<felt252>) -> u32;
}
