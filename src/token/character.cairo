use starknet::{ContractAddress, ClassHash};
use starknet::storage_access::StorePacking;
use ninth::math::pow_2;

#[derive(Copy, Drop, Serde)]
struct CharacterSkeleton {
    face: u8,
    face_color: u32,
    hair: u8,
    hair_color: u32,
    eyes: u8,
    eyes_color: u32,
    nose: u8,
    nose_color: u32,
    mouth: u8,
    mouth_color: u32,
    body: u8,
    body_color: u32,
    hands: u8,
    hands_color: u32,
}

impl CharacterSkeletonStorePacking of StorePacking<CharacterSkeleton, felt252> {
    fn pack(value: CharacterSkeleton) -> felt252 {
        let low: u128 = value.face.into() + (value.face_color.into() * pow_2(8)) + (value.hair.into() * pow_2(8*4)) + (value.hair_color.into() * pow_2(8*5)) + (value.eyes.into() * pow_2(8*8)) + (value.eyes_color.into() * pow_2(8*9)) + (value.nose.into() * pow_2(8*12)) + (value.nose_color.into() * pow_2(8*13));
        let high: u128 = value.mouth.into() + (value.mouth_color.into() * pow_2(8)) + (value.body.into() * pow_2(8*4)) + (value.body_color.into() * pow_2(8*5)) + (value.hands.into() * pow_2(8*8)) + (value.hands_color.into() * pow_2(8*9));
        u256{low, high}.try_into().unwrap()
    }

    fn unpack(value: felt252) -> CharacterSkeleton {
        let value: u256 = value.into();
        CharacterSkeleton {
            face: (value & 0xff).try_into().unwrap(),
            face_color: ((value.low / pow_2(8)) & 0xffffff).try_into().unwrap(),
            hair: ((value.low / pow_2(8*4))&0xff).try_into().unwrap(),
            hair_color: ((value.low / pow_2(8*5)) & 0xffffff).try_into().unwrap(),
            eyes: ((value.low / pow_2(8*8))&0xff).try_into().unwrap(),
            eyes_color: ((value.low / pow_2(8*9)) & 0xffffff).try_into().unwrap(),
            nose: ((value.low / pow_2(8*12))&0xff).try_into().unwrap(),
            nose_color: ((value.low / pow_2(8*13)) & 0xffffff).try_into().unwrap(),
            mouth: (value.high &0xff).try_into().unwrap(),
            mouth_color: ((value.high / pow_2(8)) & 0xffffff).try_into().unwrap(),
            body: ((value.high / pow_2(8*4))&0xff).try_into().unwrap(),
            body_color: ((value.high / pow_2(8*5)) & 0xffffff).try_into().unwrap(),
            hands: ((value.high / pow_2(8*8)) & 0xff).try_into().unwrap(),
            hands_color: ((value.high / pow_2(8*9)) & 0xffffff).try_into().unwrap(),
        }
    }
}

#[starknet::interface]
trait ICharacter<TContractState> {
    fn create_character(ref self: TContractState,  character_skeleton: felt252, uri: Array<felt252>, signature: Span<felt252>) -> u256;
    fn get_character_skeleton(self: @TContractState, token_id: u256) -> CharacterSkeleton;
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::interface]
trait IAccessControl<TContractState> {
    fn hasRole(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn getRoleAdmin(self: @TContractState, role: felt252) -> felt252;
    fn grantRole(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revokeRole(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounceRole(ref self: TContractState, role: felt252, account: ContractAddress);
}

#[starknet::contract]
mod character {

    use ninth::erc::ierc165::{IERC165, IERC165DispatcherTrait, IERC165Dispatcher, IERC165Id};
    use ninth::erc::ierc721::{IERC721, IERC721Enumerable, IERC721TokenReceiverDispatcherTrait, IERC721TokenReceiverDispatcher, IERC721TokenReceiverId, IERC721Id, IERC721MetadataId, IERC721EnumerableId};
    use starknet::{ContractAddress, ClassHash};
    use starknet::get_caller_address;
    use starknet::syscalls::replace_class_syscall;
    use core::ecdsa::check_ecdsa_signature;
    use core::poseidon::poseidon_hash_span;
    use core::num::traits::zero::Zero;
    use super::{ICharacter, IAccessControl, CharacterSkeleton, CharacterSkeletonStorePacking};

    const IAccountId: u32 = 0xa66bd575;

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleUpgrader: felt252 = selector!("RoleUpgrader");

    #[storage]
    struct Storage {
        ERC721_name: felt252,
        ERC721_symbol: felt252,
        #[feature("deprecated_legacy_map")]
        ERC721_owners: LegacyMap<u256, ContractAddress>,
        #[feature("deprecated_legacy_map")]
        ERC721_balances: LegacyMap<ContractAddress, u256>,
        #[feature("deprecated_legacy_map")]
        ERC721_token_approvals: LegacyMap<u256, ContractAddress>,
        #[feature("deprecated_legacy_map")]
        ERC721_operator_approvals: LegacyMap<(ContractAddress, ContractAddress), bool>,
        #[feature("deprecated_legacy_map")]
        ERC721_token_uri: LegacyMap<u256, felt252>,
        ERC721Enumerable_all_tokens_len: u256,
        #[feature("deprecated_legacy_map")]
        ERC721Enumerable_all_tokens: LegacyMap<u256, u256>,
        #[feature("deprecated_legacy_map")]
        ERC721Enumerable_all_tokens_index: LegacyMap<u256, u256>,
        #[feature("deprecated_legacy_map")]
        ERC721Enumerable_owned_tokens: LegacyMap<(ContractAddress, u256), u256>,
        #[feature("deprecated_legacy_map")]
        ERC721Enumerable_owned_tokens_index: LegacyMap<u256, u256>,
        #[feature("deprecated_legacy_map")]
        AccessControl_role_admin: LegacyMap<felt252, felt252>,
        #[feature("deprecated_legacy_map")]
        AccessControl_role_member: LegacyMap<(felt252, ContractAddress), bool>,

        sign_public_key: felt252,
        token_counter: u256,
        #[feature("deprecated_legacy_map")]
        token_character_skeletons: LegacyMap<u256, CharacterSkeleton>,
        #[feature("deprecated_legacy_map")]
        token_uris: LegacyMap<(u256, usize), felt252>,
        #[feature("deprecated_legacy_map")]
        token_uri_len: LegacyMap<u256, usize>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        RoleGranted: RoleGranted,
        RoleRevoked: RoleRevoked,
        RoleAdminChanged: RoleAdminChanged,
        Upgraded: Upgraded,
        CharacterCreated: CharacterCreated,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        approved: ContractAddress,
        token_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,
        approved: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct RoleGranted {
        role: felt252,
        account: ContractAddress,
        sender: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RoleRevoked {
        role: felt252,
        account: ContractAddress,
        sender: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RoleAdminChanged {
        role: felt252,
        previous_admin_role: felt252,
        new_admin_role: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash,
    }

    #[derive(Drop, starknet::Event)]
    struct CharacterCreated {
        account: ContractAddress,
        token_id: u256,
        character_skeleton: CharacterSkeleton,
        uri: Span<felt252>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, sign_public_key: felt252) {
        self._initializer('Ninth Character', 'NC', owner, sign_public_key);
    }

    #[abi(embed_v0)]
    impl ERC721 of IERC721<ContractState> {

        fn name(self: @ContractState) -> felt252 {
            self.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.ERC721_symbol.read()
        }

        fn tokenURI(self: @ContractState, token_id: u256) -> Array<felt252> {
            self._get_token_uri(token_id)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            assert(!account.is_zero(), 'ERC721: invalid account');
            self.ERC721_balances.read(account)
        }

        fn ownerOf(self: @ContractState, token_id: u256) -> ContractAddress {
            self._owner_of(token_id)
        }

        fn getApproved(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(self._exists(token_id), 'ERC721: invalid token ID');
            self.ERC721_token_approvals.read(token_id)
        }

        fn isApprovedForAll(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
            self.ERC721_operator_approvals.read((owner, operator))
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self._owner_of(token_id);
            let caller = get_caller_address();
            assert(
                owner == caller || self.isApprovedForAll(owner, caller), 'ERC721: unauthorized caller'
            );
            self._approve(to, token_id);
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            self._set_approval_for_all(get_caller_address(), operator, approved)
        }

        fn transferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
            assert(
                self._is_approved_or_owner(get_caller_address(), token_id), 'ERC721: unauthorized caller'
            );
            self._transfer(from, to, token_id);
        }

        fn safeTransferFrom(
            ref self: ContractState,from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
        ) {
            assert(
                self._is_approved_or_owner(get_caller_address(), token_id), 'ERC721: unauthorized caller'
            );
            self._transfer(from, to, token_id);
            assert(self._check_on_erc721_received(from, to, token_id, data), 'ERC721: unsafe transfer');
        }

    }

    #[abi(embed_v0)]
    impl ERC721Enumerable of IERC721Enumerable<ContractState> {
        fn totalSupply(self: @ContractState) -> u256 {
            self.ERC721Enumerable_all_tokens_len.read()
        }

        fn tokenByIndex(self: @ContractState, index: u256) -> u256 {
            let len = self.totalSupply();
            assert(index < len, 'global index out of bounds');
            self.ERC721Enumerable_all_tokens.read(index)
        }

        fn tokenOfOwnerByIndex(self: @ContractState, owner: ContractAddress, index: u256) -> u256 {
            let len = self.balanceOf(owner);
            assert(index < len, 'owner index out of bounds');
            self.ERC721Enumerable_owned_tokens.read((owner, index))
        }
    }

    #[abi(embed_v0)]
    impl AccessControl of IAccessControl<ContractState> {

        fn hasRole(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self._has_role(role, account)
        }

        fn getRoleAdmin(self: @ContractState, role: felt252) -> felt252 {
            self._get_role_admin(role)
        }

        fn grantRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let admin = self._get_role_admin(role);
            self._assert_only_role(admin);
            self._grant_role(role, account);
        }

        fn revokeRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let admin: felt252 = self._get_role_admin(role);
            self._assert_only_role(admin);
            self._revoke_role(role, account);
        }

        fn renounceRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            assert(caller == account, 'Can only renounce role for self');
            self._revoke_role(role, account);
        }

    }

    #[abi(embed_v0)]
    impl Character of ICharacter<ContractState> {

        fn create_character(ref self: ContractState,  character_skeleton: felt252, uri: Array<felt252>, signature: Span<felt252>) -> u256 {
            assert(self._validate_character_skeleton_signature(character_skeleton, uri.span(), signature), 'invalid signature');
            self._create_character(character_skeleton, uri)
        }

        fn get_character_skeleton(self: @ContractState, token_id: u256) -> CharacterSkeleton {
            self.token_character_skeletons.read(token_id)
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self._assert_only_role(RoleUpgrader);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

    }

    #[abi(embed_v0)]
    impl ERC165 of IERC165<ContractState> {
        fn supportsInterface(self: @ContractState, interface_id: u32) -> bool {
            interface_id==IERC165Id || interface_id==IERC721Id || interface_id==IERC721MetadataId || interface_id==IERC721EnumerableId
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _initializer(ref self: ContractState, name: felt252, symbol: felt252, owner: ContractAddress, sign_public_key: felt252) {
            self.ERC721_name.write(name);
            self.ERC721_symbol.write(symbol);
            self.sign_public_key.write(sign_public_key);
            self._grant_role(RoleDefaultAdmin, owner);
        }

        fn _owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let owner = self.ERC721_owners.read(token_id);
            match owner.is_zero() {
                bool::False(()) => owner,
                bool::True(()) => panic!("ERC721: invalid token ID")
            }
        }

        fn _exists(self: @ContractState, token_id: u256) -> bool {
            !self.ERC721_owners.read(token_id).is_zero()
        }

        fn _is_approved_or_owner(self: @ContractState, spender: ContractAddress, token_id: u256) -> bool {
            let owner = self._owner_of(token_id);
            owner == spender || self.isApprovedForAll(owner, spender) || spender == self.ERC721_token_approvals.read(token_id)
        }

        fn _approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self._owner_of(token_id);
            assert(owner != to, 'ERC721: approval to owner');
            self.ERC721_token_approvals.write(token_id, to);
            self.emit(Approval{owner: owner, approved: to, token_id: token_id});
        }

        fn _set_approval_for_all(ref self: ContractState, owner: ContractAddress, operator: ContractAddress, approved: bool) {
            assert(owner != operator, 'ERC721: self approval');
            self.ERC721_operator_approvals.write((owner, operator), approved);
            self.emit(ApprovalForAll{owner: owner, operator: operator, approved: approved});
        }

        fn _mint(ref self: ContractState, to: ContractAddress, token_id: u256) {
            // enumerable
            self._add_token_to_all_tokens_enumeration(token_id);
            self._add_token_to_owner_enumeration(to, token_id);

            assert(!to.is_zero(), 'ERC721: invalid receiver');
            assert(!self._exists(token_id), 'ERC721: token already minted');

            // Update balances
            self.ERC721_balances.write(to, self.ERC721_balances.read(to) + 1_u256);
            // Update token_id owner
            self.ERC721_owners.write(token_id, to);
            // Emit event
            self.emit(Transfer{from: Zero::zero(), to: to, token_id: token_id});
        }

        fn _transfer(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
            // enumerable
            self._remove_token_from_owner_enumeration(from, token_id);
            self._add_token_to_owner_enumeration(to, token_id);

            assert(!to.is_zero(), 'ERC721: invalid receiver');
            let owner = self._owner_of(token_id);
            assert(from == owner, 'ERC721: wrong sender');

            // Implicit clear approvals, no need to emit an event
            self.ERC721_token_approvals.write(token_id, Zero::zero());
            // Update balances
            self.ERC721_balances.write(from, self.ERC721_balances.read(from) - 1_u256);
            self.ERC721_balances.write(to, self.ERC721_balances.read(to) + 1_u256);

            // Update token_id owner
            self.ERC721_owners.write(token_id, to);
            // Emit event
            self.emit(Transfer{from: from, to: to, token_id: token_id});

            
        }

        fn _burn(ref self: ContractState, token_id: u256) {
            let owner = self._owner_of(token_id);
            self._remove_token_from_owner_enumeration(owner, token_id);
            self._remove_token_from_all_tokens_enumeration(token_id);
            // Implicit clear approvals, no need to emit an event
            self.ERC721_token_approvals.write(token_id, Zero::zero());
            // Update balances
            self.ERC721_balances.write(owner, self.ERC721_balances.read(owner) - 1_u256);
            // Delete owner
            self.ERC721_owners.write(token_id, Zero::zero());
            // Emit event
            self.emit(Transfer{from: owner, to: Zero::zero(), token_id: token_id});
        }

        // enumerabale
        fn _add_token_to_all_tokens_enumeration(ref self: ContractState, token_id: u256) {
            let supply = self.ERC721Enumerable_all_tokens_len.read();
            self.ERC721Enumerable_all_tokens.write(supply, token_id);
            self.ERC721Enumerable_all_tokens_index.write(token_id, supply);

            let new_supply = supply + 1;
            self.ERC721Enumerable_all_tokens_len.write(new_supply);
        }

        fn _remove_token_from_all_tokens_enumeration(ref self: ContractState, token_id: u256) {
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

        fn _add_token_to_owner_enumeration(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let length = self.balanceOf(to);
            self.ERC721Enumerable_owned_tokens.write((to, length), token_id);
            self.ERC721Enumerable_owned_tokens_index.write(token_id, length);
        }

        fn _remove_token_from_owner_enumeration(ref self: ContractState, from: ContractAddress, token_id: u256) {
            let last_token_index = self.balanceOf(from) - 1;
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


        fn _assert_only_role(self: @ContractState, role: felt252) {
            let caller: ContractAddress = get_caller_address();
            let authorized: bool = self._has_role(role, caller);
            assert(authorized, 'Caller is missing role');
        }

        fn _has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            self.AccessControl_role_member.read((role, account))
        }

        fn _grant_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            if !self._has_role(role, account) {
                let caller: ContractAddress = get_caller_address();
                self.AccessControl_role_member.write((role, account), true);
                self.emit(RoleGranted{role: role, account: account, sender: caller});
            }
        }

        fn _revoke_role(ref self: ContractState, role: felt252, account: ContractAddress) {
            if self._has_role(role, account) {
                let caller: ContractAddress = get_caller_address();
                self.AccessControl_role_member.write((role, account), false);
                self.emit(RoleRevoked{role: role, account: account, sender: caller});
            }
        }

        fn _set_role_admin(ref self: ContractState, role: felt252, admin_role: felt252) {
            let previous_admin_role: felt252 = self._get_role_admin(role);
            self.AccessControl_role_admin.write(role, admin_role);
            self.emit(RoleAdminChanged{role: role, previous_admin_role: previous_admin_role, new_admin_role: admin_role});
        }

        fn _get_role_admin(self: @ContractState, role: felt252) -> felt252 {
            self.AccessControl_role_admin.read(role)
        }

        fn _check_on_erc721_received(
            self: @ContractState, from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
        ) -> bool {
            if (IERC165Dispatcher{contract_address: to}.supportsInterface(IERC721TokenReceiverId)) {
                IERC721TokenReceiverDispatcher{contract_address: to}.onERC721Received(
                    get_caller_address(), from, token_id, data
                    ) == IERC721TokenReceiverId
            } else {
                IERC165Dispatcher{contract_address: to}.supportsInterface(IAccountId)
            }
        }
    }

    #[generate_trait]
    impl CharacterInternalImpl of CharacterInternalTrait {
        fn _get_token_uri(self: @ContractState, token_id: u256) -> Array<felt252> {
            assert(self._exists(token_id), 'ERC721: invalid token ID');
            let uri_len = self.token_uri_len.read(token_id);
            let mut i: usize = 0;
            let mut uri: Array<felt252> = ArrayTrait::new();
            loop {
                if i==uri_len {
                    break;
                }
                let item = self.token_uris.read((token_id, i));
                uri.append(item);
                i += 1;
            };
            uri
        }

        fn _set_token_uri(ref self: ContractState, token_id: u256, uri: Span<felt252>) {
            assert(self._exists(token_id), 'ERC721: invalid token ID');
            let uri_len: usize = uri.len();
            let mut i: usize = 0;
            loop {
                if i==uri_len {
                    break;
                }
                self.token_uris.write((token_id, i), *uri.at(i));
                i += 1;
            };
            self.token_uri_len.write(token_id, uri_len);
        }

        fn _create_character(ref self: ContractState, character_skeleton: felt252, uri: Array<felt252>) -> u256 {
            let caller = get_caller_address();
            let token_id = self.token_counter.read() + 1;
            self.token_counter.write(token_id);
            self._mint(caller, token_id);
            let character_skeleton_val = CharacterSkeletonStorePacking::unpack(character_skeleton);
            self.token_character_skeletons.write(token_id, character_skeleton_val);
            self._set_token_uri(token_id, uri.span());
            self.emit(CharacterCreated{account: caller, token_id: token_id, character_skeleton: character_skeleton_val, uri: uri.span()});
            token_id
        }

        fn _validate_character_skeleton_signature(self: @ContractState, character_skeleton: felt252, uri: Span<felt252>, signature: Span<felt252>) -> bool {
            if signature.len()!= 2 || uri.len()==0 {
                return false;
            }
            let caller = get_caller_address();
            let caller_felt: felt252 = caller.into();
            let mut message: Array<felt252> = array![
                caller_felt,
                character_skeleton,
            ];
            let uri_len = uri.len();
            let mut i: usize = 0;
            loop {
                if i==uri_len {
                    break;
                }
                message.append(*uri.at(i));
                i += 1;
            };
            let message_hash = poseidon_hash_span(message.span());
            let public_key = self.sign_public_key.read();
            check_ecdsa_signature(message_hash, public_key, *signature.at(0_u32), *signature.at(1_u32))
        }
    }

}

#[cfg(test)]
mod test {

    use core::debug::PrintTrait;
    use super::CharacterSkeletonStorePacking;

    #[test]
    fn test_character_unpack() {
        let character_skeleton_val = 0x12150f2b656a710207341e2074ba801212b28e150811173728575c42;
        let character_skeleton = CharacterSkeletonStorePacking::unpack(character_skeleton_val);
        assert(character_skeleton.face==0x42, 'face should be 0x42');
        assert(character_skeleton.face_color==0x28575c, 'face_color should be 0x28575c');
        assert(character_skeleton.hair==0x37, 'hair should be 0x37');
        assert(character_skeleton.hair_color==0x081117, 'hair_color should be 0x081117');
        assert(character_skeleton.eyes==0x15, 'eyes should be 0x15');
        assert(character_skeleton.eyes_color==0x12b28e, 'eyes should be 0x12b28e');
        assert(character_skeleton.nose==0x12, 'eyes should be 0x12');
        assert(character_skeleton.nose_color==0x74ba80, 'eyes should be 0x74ba80');
        assert(character_skeleton.mouth==0x20, 'mouth should be 0x12');
        assert(character_skeleton.mouth_color==0x07341e, 'mouth_color should be 0x07341e');
        assert(character_skeleton.body==0x02, 'body should be 0x02');
        assert(character_skeleton.body_color==0x656a71, 'body_color should be 0x656a71');
        assert(character_skeleton.hands==0x2b, 'hands should be 0x2b');
        assert(character_skeleton.hands_color==0x12150f, 'hands_color should be 0x12150f');
    }
}