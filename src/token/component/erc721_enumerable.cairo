// SPDX-License-Identifier: MIT
// ERC721 enumerable component based on openzeppelin ERC721 component

#[starknet::component]
pub mod ERC721EnumerableComponent {

    use ninth::interface::ierc721_enumerable::{IERC721Enumerable, IERC721EnumerableCamel, IERC721_ENUMERABLE_ID};
    use starknet::{ContractAddress, ClassHash};
    use starknet::get_caller_address;
    use core::num::traits::Zero;
    use core::option::OptionTrait;

    use openzeppelin::introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use openzeppelin::introspection::src5::SRC5Component::SRC5Impl;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721Component::ERC721Impl;
    use openzeppelin::token::erc721::ERC721Component;

    #[storage]
    struct Storage {
        ERC721Enumerable_all_tokens_len: u256,
        ERC721Enumerable_all_tokens: LegacyMap<u256, u256>,
        ERC721Enumerable_all_tokens_index: LegacyMap<u256, u256>,
        ERC721Enumerable_owned_tokens: LegacyMap<(ContractAddress, u256), u256>,
        ERC721Enumerable_owned_tokens_index: LegacyMap<u256, u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
    }

    #[embeddable_as(ERC721EnumerableImpl)]
    impl ERC721Enumerable<
        TContractState,
        +HasComponent<TContractState>,
        impl ERC721: ERC721Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721Enumerable<ComponentState<TContractState>> {
        fn total_supply(self: @ComponentState<TContractState>) -> u256 {
            self.ERC721Enumerable_all_tokens_len.read()
        }

        fn token_by_index(self: @ComponentState<TContractState>, index: u256) -> u256 {
            let len = self.totalSupply();
            assert(index < len, 'global index out of bounds');
            self.ERC721Enumerable_all_tokens.read(index)
        }

        fn token_of_owner_by_index(self: @ComponentState<TContractState>, owner: ContractAddress, index: u256) -> u256 {
            let erc721_comp = get_dep_component!(self, ERC721);
            let len = erc721_comp.ERC721_balances.read(owner);
            assert(index < len, 'owner index out of bounds');
            self.ERC721Enumerable_owned_tokens.read((owner, index))
        }
    }

    #[embeddable_as(ERC721EnumerableCamelImpl)]
    impl ERC721EnumerableCame<
        TContractState,
        +HasComponent<TContractState>,
        impl ERC721: ERC721Component::HasComponent<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>
    > of IERC721EnumerableCamel<ComponentState<TContractState>> {
        fn totalSupply(self: @ComponentState<TContractState>) -> u256 {
            ERC721Enumerable::total_supply(self)
        }

        fn tokenByIndex(self: @ComponentState<TContractState>, index: u256) -> u256 {
            ERC721Enumerable::token_by_index(self, index)
        }

        fn tokenOfOwnerByIndex(self: @ComponentState<TContractState>, owner: ContractAddress, index: u256) -> u256 {
            ERC721Enumerable::token_of_owner_by_index(self, owner, index)
        }
    }

    
    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        impl ERC721: ERC721Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>) {
            let mut src5_comp_mut = get_dep_component_mut!(ref self, SRC5);
            src5_comp_mut.register_interface(IERC721_ENUMERABLE_ID);
        }

        fn before_update(
            ref self: ComponentState<TContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) { 
            let erc721_comp = get_dep_component!(@self, ERC721);
            let owner = erc721_comp.ERC721_owners.read(token_id);
            if owner.is_zero() {
                self._add_token_to_all_tokens_enumeration(token_id);
            }else {
                self._remove_token_from_owner_enumeration(owner, token_id);
            }
            if to.is_zero() {
                self._remove_token_from_all_tokens_enumeration(token_id);
            }else {
                self._add_token_to_owner_enumeration(to, token_id);
            }
        }

        // enumerabale
        fn _add_token_to_all_tokens_enumeration(ref self: ComponentState<TContractState>, token_id: u256) {
            let supply = self.ERC721Enumerable_all_tokens_len.read();
            self.ERC721Enumerable_all_tokens.write(supply, token_id);
            self.ERC721Enumerable_all_tokens_index.write(token_id, supply);

            let new_supply = supply + 1;
            self.ERC721Enumerable_all_tokens_len.write(new_supply);
        }

        fn _remove_token_from_all_tokens_enumeration(ref self: ComponentState<TContractState>, token_id: u256) {
            let supply = self.ERC721Enumerable_all_tokens_len.read();
            let last_token_index = supply - 1;
            let token_index = self.ERC721Enumerable_all_tokens_index.read(token_id);
            let last_token_id = self.ERC721Enumerable_all_tokens.read(last_token_index);

            self.ERC721Enumerable_all_tokens.write(last_token_index, 0);
            self.ERC721Enumerable_all_tokens_index.write(token_id, 0);
            self.ERC721Enumerable_all_tokens_len.write(last_token_index);
        
            if (last_token_index != token_index) {
                self.ERC721Enumerable_all_tokens_index.write(last_token_id, token_index);
                self.ERC721Enumerable_all_tokens.write(token_index, last_token_id);
            }
        }

        fn _add_token_to_owner_enumeration(ref self: ComponentState<TContractState>, to: ContractAddress, token_id: u256) {
            let erc721_comp = get_dep_component!(@self, ERC721);
            let length = erc721_comp.ERC721_balances.read(to);
            self.ERC721Enumerable_owned_tokens.write((to, length), token_id);
            self.ERC721Enumerable_owned_tokens_index.write(token_id, length);
        }

        fn _remove_token_from_owner_enumeration(ref self: ComponentState<TContractState>, from: ContractAddress, token_id: u256) {
            let erc721_comp = get_dep_component!(@self, ERC721);
            let last_token_index = erc721_comp.ERC721_balances.read(from) - 1;
            let token_index = self.ERC721Enumerable_owned_tokens_index.read(token_id);
            if (token_index==last_token_index) {
                self.ERC721Enumerable_owned_tokens_index.write(token_id, 0);
                self.ERC721Enumerable_owned_tokens.write((from, last_token_index), 0);
            }

            let last_token_id = self.ERC721Enumerable_owned_tokens.read((from, last_token_index));
            self.ERC721Enumerable_owned_tokens.write((from, token_index), last_token_id);
            self.ERC721Enumerable_owned_tokens_index.write(last_token_id, token_index);
            return ();
        }
    }

}
