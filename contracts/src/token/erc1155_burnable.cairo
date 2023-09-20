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
trait IERC1155Burnable<TContractState> {
    fn setTokenUri(ref self: TContractState, id: u256, uri: Span<felt252>);
    fn burn(ref self: TContractState, id: u256, value: u256);
    fn burnBatch(ref self: TContractState, ids: Span<u256>, values: Span<u256>);
    fn safeMint(ref self: TContractState, to: ContractAddress, id: u256, value: u256, data: Span<felt252>);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
    
    fn mint(ref self: TContractState, to: ContractAddress, id: u256, value: u256);
    fn transferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, id: u256, value: u256);
    fn batchTransferFrom(ref self: TContractState, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>);
}

#[starknet::contract]
mod erc1155_burnable {
    use super::{IAccessControl, IERC1155Burnable};
    use ninth::erc::ierc165::{IERC165, IERC165DispatcherTrait, IERC165Dispatcher, IERC165Id};
    use ninth::erc::ierc1155::{IERC1155, IERC1155MetadataURI, IERC1155TokenReceiverDispatcherTrait, IERC1155TokenReceiverDispatcher, IERC1155Id, IERC1155TokenReceiverId, IERC1155MetadataURIId, IERC1155ReceivedSelector, IERC1155BatchReceivedSelector};
    use starknet::{ContractAddress, ClassHash};
    use starknet::get_caller_address;
    use starknet::syscalls::replace_class_syscall;
    use zeroable::Zeroable;
    use option::OptionTrait;
    use array::{ArrayTrait, SpanTrait};
    use result::ResultTrait;
    use traits::{Into, TryInto};

    const IAccountId: u32 = 0xa66bd575;

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleAdmin: felt252 = 0xaffd781351ea8ad3cd67f64a8ffa5919206623ec343d2583ab317bb5bd2b82;
    const RoleMinter: felt252 = 0x14a29a7a52126dd9ed87a315096a38eeae324f6f3ca318bc444b62a9ed9375a;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;

    #[storage]
    struct Storage {
        ERC1155_balances: LegacyMap<(u256, ContractAddress), u256>,
        ERC1155_operator_approvals: LegacyMap<(ContractAddress, ContractAddress), bool>,
        ERC1155_token_uri_len: LegacyMap<u256, usize>,
        ERC1155_token_uri: LegacyMap<(u256, usize), felt252>,
        AccessControl_role_admin: LegacyMap<felt252, felt252>,
        AccessControl_role_member: LegacyMap<(felt252, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TransferSingle: TransferSingle,
        TransferBatch: TransferBatch,
        ApprovalForAll: ApprovalForAll,
        URI: URI,
        RoleGranted: RoleGranted,
        RoleRevoked: RoleRevoked,
        RoleAdminChanged: RoleAdminChanged,
        Upgraded: Upgraded,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferSingle {
        operator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,

        id: u256,
        value: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferBatch {
        operator: ContractAddress,
        from: ContractAddress,
        to: ContractAddress,

        ids: Span<u256>,
        values: Span<u256>,
    }

    #[derive(Drop, starknet::Event)]
    struct ApprovalForAll {
        owner: ContractAddress,
        operator: ContractAddress,

        approved: bool,
    }

    #[derive(Drop, starknet::Event)]
    struct URI {
        value: Span<felt252>,
        id: u256,
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
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self._grant_role(RoleDefaultAdmin, owner);
    }

    #[external(v0)]
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

    #[external(v0)]
    impl ERC1155Burnable of IERC1155Burnable<ContractState> {
        fn setTokenUri(ref self: ContractState, id: u256, uri: Span<felt252>) {
            self._assert_only_role(RoleAdmin);
            self._set_token_uri(id, uri);
        }

        fn safeMint(ref self: ContractState, to: ContractAddress, id: u256, value: u256, data: Span<felt252>) {
            self._assert_only_role(RoleMinter);
            let caller = get_caller_address();
            self._safe_mint(caller, to, id, value, data);
        }

        fn burn(ref self: ContractState, id: u256, value: u256) {
            let caller = get_caller_address();
            self._burn(caller, caller, id, value);
        }

        fn burnBatch(ref self: ContractState, ids: Span<u256>, values: Span<u256>) {
            let caller = get_caller_address();
            self._burn_batch(caller, caller, ids, values);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self._assert_only_role(RoleUpgrader);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

        fn mint(ref self: ContractState, to: ContractAddress, id: u256, value: u256) {
            self._assert_only_role(RoleMinter);
            let caller = get_caller_address();
            self._mint(caller, to, id, value);
        }

        fn transferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, id: u256, value: u256) {
            let caller = get_caller_address();
            assert(self._is_owner_or_approved(caller, from), 'not owner nor approved');
            self._transfer_from(caller, from, to, id, value);
        }
        
        fn batchTransferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>) {
            let caller = get_caller_address();
            assert(self._is_owner_or_approved(caller, from), 'not owner nor approved');
            self._batch_transfer_from(caller, from, to, ids, values);
        }
    }

    #[external(v0)]
    impl ERC165 of IERC165<ContractState> {
        fn supportsInterface(self: @ContractState, interface_id: u32) -> bool {
            interface_id==IERC165Id || interface_id==IERC1155Id || interface_id==IERC1155MetadataURIId
        }
    }

    #[external(v0)]
    impl ERC1155 of IERC1155<ContractState> {
        fn balanceOf(self: @ContractState, account: ContractAddress, id: u256) -> u256 {
            self.ERC1155_balances.read((id, account))
        }

        fn balanceOfBatch(self: @ContractState, accounts: Span<ContractAddress>, ids: Span<u256>) -> Span<u256> {
            let len = accounts.len();
            assert(len == ids.len(), 'array length mismatch');
            let mut balances = array![];
            let mut i: usize = 0;
            loop {
                if i == len {
                    break balances.span();
                }
                balances.append(self.ERC1155_balances.read((*ids.at(i), *accounts.at(i))));
                i += 1;
            }
        }

        fn isApprovedForAll(self: @ContractState, owner: ContractAddress, operator: ContractAddress) -> bool {
            self.ERC1155_operator_approvals.read((owner, operator))
        }

        fn setApprovalForAll(ref self: ContractState, operator: ContractAddress, approved: bool) {
            let caller = get_caller_address();
            self._set_approval_for_all(caller, operator, approved);
        }

        fn safeTransferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, id: u256, value: u256, data: Span<felt252>) {
            let caller = get_caller_address();
            assert(self._is_owner_or_approved(caller, from), 'not owner nor approved');
            self._safe_transfer_from(caller, from, to, id, value, data);
        }

        fn safeBatchTransferFrom(ref self: ContractState, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>) {
            let caller = get_caller_address();
            assert(self._is_owner_or_approved(caller, from), 'not owner nor approved');
            self._safe_batch_transfer_from(caller, from, to, ids, values, data);
        }
    }

    #[external(v0)]
    impl ERC1155MetadataURI of IERC1155MetadataURI<ContractState> {
        fn uri(self: @ContractState, id: u256) -> Span<felt252> {
            let uri_len: usize = self.ERC1155_token_uri_len.read(id);
            let mut i: usize = 0;
            let mut uri: Array<felt252> = ArrayTrait::new();
            loop {
                if i==uri_len {
                    break uri.span();
                }
                let item = self.ERC1155_token_uri.read((id, i));
                uri.append(item);
                i += 1;
            }
        }
    }

    #[generate_trait]
    impl ERC1155Interal of IERC1155InternalTrait {

        fn __transfer(ref self: ContractState, from: ContractAddress, to: ContractAddress, id: u256, value: u256) {
            assert(to != Zeroable::zero(), 'transfer to the zero address');
            let from_balance = self.ERC1155_balances.read((id, from));
            assert(from_balance >= value, 'insufficient balance');
            let new_from_balance = from_balance - value;
            self.ERC1155_balances.write((id, from), new_from_balance);
            let to_balance = self.ERC1155_balances.read((id, to));
            let new_to_balance = to_balance + value;
            self.ERC1155_balances.write((id, to), new_to_balance);
        }

        fn __check_on_erc1155_received(self: @ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, id: u256, value: u256, data: Span<felt252>) -> bool {
            if (IERC165Dispatcher{contract_address: to}.supportsInterface(IERC1155TokenReceiverId)) {
                IERC1155TokenReceiverDispatcher{contract_address: to}.onERC1155Received(
                    operator, from, id, value, data
                    ) == IERC1155ReceivedSelector
            } else {
                IERC165Dispatcher{contract_address: to}.supportsInterface(IAccountId)
            }
        }

        fn __check_on_erc1155_batch_received(self: @ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>) -> bool {
            if (IERC165Dispatcher{contract_address: to}.supportsInterface(IERC1155TokenReceiverId)) {
                IERC1155TokenReceiverDispatcher{contract_address: to}.onERC1155BatchReceived(
                    operator, from, ids, values, data
                    ) == IERC1155BatchReceivedSelector
            } else {
                IERC165Dispatcher{contract_address: to}.supportsInterface(IAccountId)
            }
        }

        fn _is_owner_or_approved(self: @ContractState, operator: ContractAddress, owner: ContractAddress) -> bool {
            if operator == owner {
                return true;
            }
            self.ERC1155_operator_approvals.read((owner, operator))
        }

        fn _transfer_from(ref self: ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, id: u256, value: u256) {
            self.__transfer(from, to, id, value);
            self.emit(TransferSingle{operator: operator, from: from, to: to, id: id, value: value});
        }

        fn _safe_transfer_from(ref self: ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, id: u256, value: u256, data: Span<felt252>) {
            self._transfer_from(operator, from, to, id, value);
            assert(self.__check_on_erc1155_received(operator, from, to, id, value, data), 'unsafe transfer');
        }

        fn _batch_transfer_from(ref self: ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>) {
            let len = ids.len();
            assert(len == values.len(), 'ids and values length mismatch');
            let mut i: usize = 0;
            loop {
                if i==len {
                    break;
                }
                self.__transfer(from, to, *ids.at(i), *values.at(i));
                i += 1;
            };
            self.emit(TransferBatch{operator: operator, from: from, to: to, ids: ids, values: values});
        }

        fn _safe_batch_transfer_from(ref self: ContractState, operator: ContractAddress, from: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>) {
            self._batch_transfer_from(operator, from, to, ids, values);
            assert(self.__check_on_erc1155_batch_received(operator, from, to, ids, values, data), 'unsafe transfer');
        }

        fn _mint(ref self: ContractState, operator: ContractAddress, to: ContractAddress, id: u256, value: u256) {
            let zero_address: ContractAddress = Zeroable::zero();
            assert(to != zero_address, 'mint to the zero address');
            let to_balance = self.ERC1155_balances.read((id, to));
            let new_to_balance = to_balance + value;
            self.ERC1155_balances.write((id, to), new_to_balance);

            self.emit(TransferSingle{operator: operator, from: zero_address, to: to, id: id, value: value});
        }

        fn _safe_mint(ref self: ContractState, operator: ContractAddress, to: ContractAddress, id: u256, value: u256, data: Span<felt252>) {
            self._mint(operator, to, id, value);
            assert(self.__check_on_erc1155_received(operator, Zeroable::zero(), to, id, value, data), 'unsafe mint');
        }

        fn _mint_batch(ref self: ContractState, operator: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>) {
            let zero_address: ContractAddress = Zeroable::zero();
            assert(to != zero_address, 'mint to the zero address');
            let len = ids.len();
            assert(len == values.len(), 'ids and values length mismatch');

            let mut i: usize = 0;
            loop {
                if i == len {
                    break;
                }
                let id = *ids.at(i);
                let to_balance = self.ERC1155_balances.read((id, to));
                let new_to_balance = to_balance + *values.at(i);
                self.ERC1155_balances.write((id, to), new_to_balance);
                i += 1;
            };

            let operator = get_caller_address();
            self.emit(TransferBatch{operator: operator, from: zero_address, to: to, ids: ids, values: values});
        }

        fn _safe_mint_batch(ref self: ContractState, operator: ContractAddress, to: ContractAddress, ids: Span<u256>, values: Span<u256>, data: Span<felt252>) {
            self._mint_batch(operator, to, ids, values);
            assert(self.__check_on_erc1155_batch_received(operator, Zeroable::zero(), to, ids, values, data), 'unsafe mint batch');
        }

        fn _burn(ref self: ContractState, operator: ContractAddress, from: ContractAddress, id: u256, value: u256) {
            let zero_address: ContractAddress = Zeroable::zero();
            assert(from != zero_address, 'burn from the zero address');
            let from_balance = self.ERC1155_balances.read((id, from));
            assert(from_balance >= value, 'burn value exceeds balance');
            let new_from_balance = from_balance - value;
            self.ERC1155_balances.write((id, from), new_from_balance);
            
            self.emit(TransferSingle{operator: operator, from: from, to: zero_address, id: id, value: value});
            return ();
        }

        fn _burn_batch(ref self: ContractState, operator: ContractAddress, from: ContractAddress, ids: Span<u256>, values: Span<u256>) {
            let zero_address: ContractAddress = Zeroable::zero();
            assert(from != zero_address, 'burn from the zero address');
            let len = ids.len();
            assert(len == values.len(), 'ids and values length mismatch');
            let mut i: usize = 0;
            loop {
                if i == len {
                    break;
                }
                let id = *ids.at(i);
                let value = *values.at(i);
                let from_balance = self.ERC1155_balances.read((id, from));
                assert(from_balance >= value, 'burn value exceeds balance');
                let new_from_balance = from_balance - value;
                self.ERC1155_balances.write((id, from), new_from_balance);
                i += 1;
            };

            self.emit(TransferBatch{operator: operator, from: from, to: zero_address, ids: ids, values: values});
            return ();
        }

        fn _set_approval_for_all(ref self: ContractState, owner: ContractAddress, operator: ContractAddress, approved: bool) {
            let zero_address: ContractAddress = Zeroable::zero();
            assert(operator != zero_address, 'approve for zero address');
            assert(owner != operator, 'approve for self');
            self.ERC1155_operator_approvals.write((owner, operator), approved);
            self.emit(ApprovalForAll{owner: owner, operator: operator, approved: approved});
        }

        fn _set_token_uri(ref self: ContractState, id: u256, uri: Span<felt252>) {
            let uri_len: usize = uri.len();
            let mut i: usize = 0;
            loop {
                if i == uri_len {
                    break;
                }
                self.ERC1155_token_uri.write((id, i), *uri.at(i));
                i += 1;
            };
            self.ERC1155_token_uri_len.write(id, uri_len);
            self.emit(URI{value: uri, id: id});
        }
    }

    #[generate_trait]
    impl AccessControlInternal of AccessControlInternalTrait {
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
    }
}
