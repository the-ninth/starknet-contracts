use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IAccessControl<TContractState> {
    fn hasRole(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn getRoleAdmin(self: @TContractState, role: felt252) -> felt252;
    fn grantRole(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revokeRole(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounceRole(ref self: TContractState, role: felt252, account: ContractAddress);
}

#[starknet::interface]
trait ICityPasscard<TContractState> {
    fn getPasscardCity(self: @TContractState, token_id: u256) -> u32;
    fn getCityUri(self: @TContractState, city: u32) -> Array<felt252>;
    fn setCityUri(ref self: TContractState, city: u32, uri: Array<felt252>);
    fn mint(ref self: TContractState, to: ContractAddress, city: u32) -> u256;
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::contract]
mod city_passcard {

    use super::{IAccessControl, ICityPasscard};
    use ninth::erc::ierc165::{IERC165, IERC165DispatcherTrait, IERC165Dispatcher, IERC165Id};
    use ninth::erc::ierc721::{IERC721, IERC721Enumerable, IERC721TokenReceiverDispatcherTrait, IERC721TokenReceiverDispatcher, IERC721TokenReceiverId, IERC721Id, IERC721MetadataId, IERC721EnumerableId};
    use starknet::{ContractAddress, ClassHash};
    use starknet::get_caller_address;
    use starknet::syscalls::replace_class_syscall;
    use zeroable::Zeroable;
    use option::OptionTrait;
    use array::ArrayTrait;
    use result::ResultTrait;
    use traits::{Into, TryInto};

    const IAccountId: u32 = 0xa66bd575;

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleMinter: felt252 = 0x14a29a7a52126dd9ed87a315096a38eeae324f6f3ca318bc444b62a9ed9375a;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;

    #[storage]
    struct Storage {
        ERC721_name: felt252,
        ERC721_symbol: felt252,
        ERC721_owners: LegacyMap<u256, ContractAddress>,
        ERC721_balances: LegacyMap<ContractAddress, u256>,
        ERC721_token_approvals: LegacyMap<u256, ContractAddress>,
        ERC721_operator_approvals: LegacyMap<(ContractAddress, ContractAddress), bool>,
        ERC721_token_uri: LegacyMap<u256, felt252>,
        ERC721Enumerable_all_tokens_len: u256,
        ERC721Enumerable_all_tokens: LegacyMap<u256, u256>,
        ERC721Enumerable_all_tokens_index: LegacyMap<u256, u256>,
        ERC721Enumerable_owned_tokens: LegacyMap<(ContractAddress, u256), u256>,
        ERC721Enumerable_owned_tokens_index: LegacyMap<u256, u256>,
        AccessControl_role_admin: LegacyMap<felt252, felt252>,
        AccessControl_role_member: LegacyMap<(felt252, ContractAddress), bool>,
        CityPasscard_city_uri_len: LegacyMap<u32, usize>, // city -> uri_len
        CityPasscard_city_uri: LegacyMap<(u32, usize), felt252>, // (city, index) -> res
        CityPasscard_token_counter: u256,
        CityPasscard_token_city: LegacyMap<u256, u32>, // token_id -> city
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

    #[constructor]
    fn constructor(ref self: ContractState, name: felt252, symbol: felt252, owner: ContractAddress) {
        _initializer(ref self, name, symbol, owner);
    }

    #[external(v0)]
    impl ERC721 of IERC721<ContractState> {

        fn name(self: @ContractState) -> felt252 {
            self.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.ERC721_symbol.read()
        }

        fn tokenURI(self: @ContractState, token_id: u256) -> Array<felt252> {
            assert(_exists(self, token_id), 'ERC721: invalid token ID');
            let city = self.CityPasscard_token_city.read(token_id);
            self.getCityUri(city)
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            assert(!account.is_zero(), 'ERC721: invalid account');
            self.ERC721_balances.read(account)
        }

        fn ownerOf(self: @ContractState, token_id: u256) -> ContractAddress {
            _owner_of(self, token_id)
        }

        fn getApproved(self: @ContractState, token_id: u256) -> ContractAddress {
            assert(_exists(self, token_id), 'ERC721: invalid token ID');
            self.ERC721_token_approvals.read(token_id)
        }

        fn isApprovedForAll(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
            self.ERC721_operator_approvals.read((owner, operator))
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = _owner_of(@self, token_id);
            let caller = get_caller_address();
            assert(
                owner == caller || self.isApprovedForAll(owner, caller), 'ERC721: unauthorized caller'
            );
            _approve(ref self, to, token_id);
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            _set_approval_for_all(ref self, get_caller_address(), operator, approved)
        }

        fn transferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
            assert(
                _is_approved_or_owner(@self, get_caller_address(), token_id), 'ERC721: unauthorized caller'
            );
            _transfer(ref self, from, to, token_id);
        }

        fn safeTransferFrom(
            ref self: ContractState,from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
        ) {
            assert(
                _is_approved_or_owner(@self, get_caller_address(), token_id), 'ERC721: unauthorized caller'
            );
            _transfer(ref self, from, to, token_id);
            assert(_check_on_erc721_received(from, to, token_id, data), 'ERC721: unsafe transfer');
        }

    }

    #[external(v0)]
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

    #[external(v0)]
    impl AccessControl of IAccessControl<ContractState> {

        fn hasRole(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
            _has_role(self, role, account)
        }

        fn getRoleAdmin(self: @ContractState, role: felt252) -> felt252 {
            _get_role_admin(self, role)
        }

        fn grantRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let admin = _get_role_admin(@self, role);
            _assert_only_role(@self, admin);
            _grant_role(ref self, role, account);
        }

        fn revokeRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let admin: felt252 =_get_role_admin(@self, role);
            _assert_only_role(@self, admin);
            _revoke_role(ref self, role, account);
        }

        fn renounceRole(ref self: ContractState, role: felt252, account: ContractAddress) {
            let caller: ContractAddress = get_caller_address();
            assert(caller == account, 'Can only renounce role for self');
            _revoke_role(ref self, role, account);
        }

    }

    #[external(v0)]
    impl CityPasscard of ICityPasscard<ContractState> {

        fn getPasscardCity(self: @ContractState, token_id: u256) -> u32 {
            self.CityPasscard_token_city.read(token_id)
        }

        fn getCityUri(self: @ContractState, city: u32) -> Array<felt252> {
            let uri_len: usize = self.CityPasscard_city_uri_len.read(city);
            let mut i: usize = 0;
            let mut uri: Array<felt252> = ArrayTrait::new();
            loop {
                if i==uri_len {
                    break;
                }
                let item = self.CityPasscard_city_uri.read((city, i));
                uri.append(item);
                i += 1;
            };
            uri
        }

        fn setCityUri(ref self: ContractState, city: u32, uri: Array<felt252>) {
            _assert_only_role(@self, RoleDefaultAdmin);
            let uri_len: usize = uri.len();
            let mut i: usize = 0;
            loop {
                if i==uri_len {
                    break;
                }
                self.CityPasscard_city_uri.write((city, i), *uri.at(i));
                i += 1;
            };
            self.CityPasscard_city_uri_len.write(city, uri_len);
        }

        fn mint(ref self: ContractState, to: ContractAddress, city: u32) -> u256 {
            _assert_only_role(@self, RoleMinter);
            let uri_len = self.CityPasscard_city_uri_len.read(city);
            assert(uri_len > 0, 'uri not set');
            let count = self.CityPasscard_token_counter.read();
            let token_id = count + 1;
            _mint(ref self, to, token_id);
            self.CityPasscard_token_counter.write(token_id);
            self.CityPasscard_token_city.write(token_id, city);
            token_id
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            _assert_only_role(@self, RoleUpgrader);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

    }

    #[external(v0)]
    impl ERC165 of IERC165<ContractState> {

        fn supportsInterface(self: @ContractState, interface_id: u32) -> bool {
            interface_id==IERC165Id || interface_id==IERC721Id || interface_id==IERC721MetadataId || interface_id==IERC721EnumerableId
        }

    }

    fn _initializer(ref self: ContractState, name: felt252, symbol: felt252, owner: ContractAddress) {
        self.ERC721_name.write(name);
        self.ERC721_symbol.write(symbol);
        _grant_role(ref self, RoleDefaultAdmin, owner);
    }

    fn _owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
        let owner = self.ERC721_owners.read(token_id);
        match owner.is_zero() {
            bool::False(()) => owner,
            bool::True(()) => panic_with_felt252('ERC721: invalid token ID')
        }
    }

    fn _exists(self: @ContractState, token_id: u256) -> bool {
        !self.ERC721_owners.read(token_id).is_zero()
    }

    fn _is_approved_or_owner(self: @ContractState, spender: ContractAddress, token_id: u256) -> bool {
        let owner = _owner_of(self, token_id);
        owner == spender || self.isApprovedForAll(owner, spender) || spender == self.ERC721_token_approvals.read(token_id)
    }

    fn _approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
        let owner = _owner_of(@self, token_id);
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
        _add_token_to_all_tokens_enumeration(ref self, token_id);
        _add_token_to_owner_enumeration(ref self, to, token_id);

        assert(!to.is_zero(), 'ERC721: invalid receiver');
        assert(!_exists(@self, token_id), 'ERC721: token already minted');

        // Update balances
        self.ERC721_balances.write(to, self.ERC721_balances.read(to) + 1_u256);
        // Update token_id owner
        self.ERC721_owners.write(token_id, to);
        // Emit event
        self.emit(Transfer{from: Zeroable::zero(), to: to, token_id: token_id});
    }

    fn _transfer(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
        // enumerable
        _remove_token_from_owner_enumeration(ref self, from, token_id);
        _add_token_to_owner_enumeration(ref self, to, token_id);

        assert(!to.is_zero(), 'ERC721: invalid receiver');
        let owner = _owner_of(@self, token_id);
        assert(from == owner, 'ERC721: wrong sender');

        // Implicit clear approvals, no need to emit an event
        self.ERC721_token_approvals.write(token_id, Zeroable::zero());
        // Update balances
        self.ERC721_balances.write(from, self.ERC721_balances.read(from) - 1_u256);
        self.ERC721_balances.write(to, self.ERC721_balances.read(to) + 1_u256);

        // Update token_id owner
        self.ERC721_owners.write(token_id, to);
        // Emit event
        self.emit(Transfer{from: from, to: to, token_id: token_id});

        
    }

    fn _burn(ref self: ContractState, token_id: u256) {
        let owner = _owner_of(@self, token_id);
        _remove_token_from_owner_enumeration(ref self, owner, token_id);
        _remove_token_from_all_tokens_enumeration(ref self, token_id);
        // Implicit clear approvals, no need to emit an event
        self.ERC721_token_approvals.write(token_id, Zeroable::zero());
        // Update balances
        self.ERC721_balances.write(owner, self.ERC721_balances.read(owner) - 1_u256);
        // Delete owner
        self.ERC721_owners.write(token_id, Zeroable::zero());
        // Emit event
        self.emit(Transfer{from: owner, to: Zeroable::zero(), token_id: token_id});
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
        let authorized: bool = _has_role(self, role, caller);
        assert(authorized, 'Caller is missing role');
    }

    fn _has_role(self: @ContractState, role: felt252, account: ContractAddress) -> bool {
        self.AccessControl_role_member.read((role, account))
    }

    fn _grant_role(ref self: ContractState, role: felt252, account: ContractAddress) {
        if !_has_role(@self, role, account) {
            let caller: ContractAddress = get_caller_address();
            self.AccessControl_role_member.write((role, account), true);
            self.emit(RoleGranted{role: role, account: account, sender: caller});
        }
    }

    fn _revoke_role(ref self: ContractState, role: felt252, account: ContractAddress) {
        if _has_role(@self, role, account) {
            let caller: ContractAddress = get_caller_address();
            self.AccessControl_role_member.write((role, account), false);
            self.emit(RoleRevoked{role: role, account: account, sender: caller});
        }
    }

    fn _set_role_admin(ref self: ContractState, role: felt252, admin_role: felt252) {
        let previous_admin_role: felt252 = _get_role_admin(@self, role);
        self.AccessControl_role_admin.write(role, admin_role);
        self.emit(RoleAdminChanged{role: role, previous_admin_role: previous_admin_role, new_admin_role: admin_role});
    }

    fn _get_role_admin(self: @ContractState, role: felt252) -> felt252 {
        self.AccessControl_role_admin.read(role)
    }

    fn _check_on_erc721_received(
        from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
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
