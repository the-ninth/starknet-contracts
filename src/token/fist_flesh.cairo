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
trait IFistFlesh<TContractState> {
    fn setTokenUri(ref self: TContractState, uri: Array<felt252>);
    fn mint(ref self: TContractState, to: ContractAddress) -> u256;
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::contract]
mod fist_flesh {

    use super::{IAccessControl, IFistFlesh};
    use ninth::erc::ierc165::{IERC165, IERC165DispatcherTrait, IERC165Dispatcher, IERC165Id};
    use ninth::erc::ierc721::{IERC721, IERC721Enumerable, IERC721TokenReceiverDispatcherTrait, IERC721TokenReceiverDispatcher, IERC721TokenReceiverId, IERC721Id, IERC721MetadataId, IERC721EnumerableId};
    use starknet::{ContractAddress, ClassHash};
    use starknet::get_caller_address;
    use starknet::syscalls::replace_class_syscall;
    use core::num::traits::zero::Zero;
    
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
        ERC721_token_uri_len: usize,
        ERC721_token_uri: LegacyMap<usize, felt252>,
        AccessControl_role_admin: LegacyMap<felt252, felt252>,
        AccessControl_role_member: LegacyMap<(felt252, ContractAddress), bool>,
        FistFlesh_token_counter: u256,
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

    #[abi(embed_v0)]
    impl ERC721 of IERC721<ContractState> {

        fn name(self: @ContractState) -> felt252 {
            self.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.ERC721_symbol.read()
        }

        fn tokenURI(self: @ContractState, token_id: u256) -> Array<felt252> {
            assert(_exists(self, token_id), 'ERC721: invalid token ID');
            let mut i: usize = 0;
            let mut data: Array<felt252> = array![];
            let len = self.ERC721_token_uri_len.read();
            loop {
                if i==len {
                    break;
                }
                data.append(self.ERC721_token_uri.read(i));
                i += 1;
            };
            data
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
            panic!("token bounded");
        }

        fn safeTransferFrom(
            ref self: ContractState,from: ContractAddress, to: ContractAddress, token_id: u256, data: Span<felt252>
        ) {
            panic!("token bounded");
        }

    }

    #[abi(embed_v0)]
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

    #[abi(embed_v0)]
    impl FistFlesh of IFistFlesh<ContractState> {

        fn setTokenUri(ref self: ContractState, uri: Array<felt252>) {
            _assert_only_role(@self, RoleDefaultAdmin);
            let uri_len: usize = uri.len();
            let mut i: usize = 0;
            loop {
                if i==uri_len {
                    break;
                }
                self.ERC721_token_uri.write(i, *uri.at(i));
                i += 1;
            };
            self.ERC721_token_uri_len.write(uri_len);
        }

        fn mint(ref self: ContractState, to: ContractAddress) -> u256 {
            _assert_only_role(@self, RoleMinter);
            let balance = self.balanceOf(to);
            assert(balance==0, 'duplicated mint');
            let count = self.FistFlesh_token_counter.read();
            let token_id = count + 1;
            _mint(ref self, to, token_id);
            self.FistFlesh_token_counter.write(token_id);
            token_id
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            _assert_only_role(@self, RoleUpgrader);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

    }

    #[abi(embed_v0)]
    impl ERC165 of IERC165<ContractState> {

        fn supportsInterface(self: @ContractState, interface_id: u32) -> bool {
            interface_id==IERC165Id || interface_id==IERC721Id || interface_id==IERC721MetadataId
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
            bool::True(()) => panic!("ERC721: invalid token ID")
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
        assert(!to.is_zero(), 'ERC721: invalid receiver');
        assert(!_exists(@self, token_id), 'ERC721: token already minted');

        // Update balances
        self.ERC721_balances.write(to, self.ERC721_balances.read(to) + 1_u256);
        // Update token_id owner
        self.ERC721_owners.write(token_id, to);
        // Emit event
        self.emit(Transfer{from: Zero::zero(), to: to, token_id: token_id});
    }

    fn _transfer(ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256) {
        assert(!to.is_zero(), 'ERC721: invalid receiver');
        let owner = _owner_of(@self, token_id);
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
        let owner = _owner_of(@self, token_id);
        // Implicit clear approvals, no need to emit an event
        self.ERC721_token_approvals.write(token_id, Zero::zero());
        // Update balances
        self.ERC721_balances.write(owner, self.ERC721_balances.read(owner) - 1_u256);
        // Delete owner
        self.ERC721_owners.write(token_id, Zero::zero());
        // Emit event
        self.emit(Transfer{from: owner, to: Zero::zero(), token_id: token_id});
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
