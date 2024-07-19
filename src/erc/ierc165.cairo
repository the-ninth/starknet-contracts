pub const IERC165Id: u32 = 0x01ffc9a7;

#[starknet::interface]
pub trait IERC165<TContractState> {
    fn supportsInterface(self: @TContractState, interface_id: u32) -> bool;
}