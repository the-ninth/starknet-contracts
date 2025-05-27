use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IUpgrade<TContractState> {
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
mod noah {

    use ninth::erc::ierc20::IERC20;
    use ninth::token::imintable::IMintable;
    use super::IAccessControl;
    use core::num::traits::Bounded;
    use core::num::traits::zero::Zero;
    use starknet::{ContractAddress, ClassHash};
    use starknet::{get_caller_address};
    use starknet::syscalls::replace_class_syscall;

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleMinter: felt252 = 0x14a29a7a52126dd9ed87a315096a38eeae324f6f3ca318bc444b62a9ed9375a;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;
    

    #[storage]
    struct Storage {
        ERC20_name: felt252,
        ERC20_symbol: felt252,
        ERC20_decimals: u8,
        ERC20_total_supply: u256,
        #[feature("deprecated_legacy_map")]
        ERC20_balances: LegacyMap<ContractAddress, u256>,
        #[feature("deprecated_legacy_map")]
        ERC20_allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        #[feature("deprecated_legacy_map")]
        AccessControl_role_admin: LegacyMap<felt252, felt252>,
        #[feature("deprecated_legacy_map")]
        AccessControl_role_member: LegacyMap<(felt252, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        RoleGranted: RoleGranted,
        RoleRevoked: RoleRevoked,
        RoleAdminChanged: RoleAdminChanged,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        #[key]
        owner: ContractAddress,
        #[key]
        spender: ContractAddress,
        amount: u256,
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

    #[constructor]
    fn constructor(
        ref self: ContractState, admin: ContractAddress
    ) {
        _initializer(ref self, 'Ninth Noah', 'NOAH', 0);
        _grant_role(ref self, RoleDefaultAdmin, admin);
    }


    #[abi(embed_v0)]
    impl ERC20 of IERC20<ContractState> {
        
        fn name(self: @ContractState) -> felt252 {
            self.ERC20_name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self.ERC20_symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self.ERC20_decimals.read()
        }

        fn totalSupply(self: @ContractState) -> u256 {
            self.ERC20_total_supply.read()
        }

        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.ERC20_balances.read(account)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.ERC20_allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            _transfer(ref self, sender, recipient, amount);
            true
        }

        fn transferFrom(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let caller = get_caller_address();
            _spend_allowance(ref self, sender, caller, amount);
            _transfer(ref self, sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            _approve(ref self, caller, spender, amount);
            true
        }

        fn increaseAllowance(ref self: ContractState, spender: ContractAddress, added_value: u256) -> bool {
            _increase_allowance(ref self, spender, added_value)
        }

        fn decreaseAllowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) -> bool {
            _decrease_allowance(ref self, spender, subtracted_value)
        }

    }

    #[abi(embed_v0)]
    impl Mintable of IMintable<ContractState> {
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            _assert_only_role(@self, RoleMinter);
            _mint(ref self, to, amount);
        }
    }

    #[abi(embed_v0)]
    impl Upgrade of super::IUpgrade<ContractState> {
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            _assert_only_role(@self, RoleUpgrader);
            replace_class_syscall(class_hash).unwrap();
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


    fn _initializer(ref self: ContractState, name_: felt252, symbol_: felt252, decimals_: u8) {
        self.ERC20_name.write(name_);
        self.ERC20_symbol.write(symbol_);
        self.ERC20_decimals.write(decimals_);
    }

    fn _increase_allowance(ref self: ContractState, spender: ContractAddress, added_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.ERC20_allowances.read((caller, spender)) + added_value);
        true
    }

    fn _decrease_allowance(ref self: ContractState, spender: ContractAddress, subtracted_value: u256) -> bool {
        let caller = get_caller_address();
        _approve(ref self, caller, spender, self.ERC20_allowances.read((caller, spender)) - subtracted_value);
        true
    }

    fn _mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
        assert(!recipient.is_zero(), 'ERC20: mint to 0');
        self.ERC20_total_supply.write(self.ERC20_total_supply.read() + amount);
        self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
        self.emit(Transfer { from: Zero::zero(), to: recipient, amount: amount});
    }

    fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        self.ERC20_total_supply.write(self.ERC20_total_supply.read() - amount);
        self.ERC20_balances.write(account, self.ERC20_balances.read(account) - amount);
        self.emit(Transfer { from: account, to: Zero::zero(), amount: amount});
    }

    fn _approve(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        assert(!owner.is_zero(), 'ERC20: approve from 0');
        assert(!spender.is_zero(), 'ERC20: approve to 0');
        self.ERC20_allowances.write((owner, spender), amount);
        self.emit(Approval { owner: owner, spender: spender, amount: amount });
    }

    fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
        assert(!sender.is_zero(), 'ERC20: transfer from 0');
        assert(!recipient.is_zero(), 'ERC20: transfer to 0');
        self.ERC20_balances.write(sender, self.ERC20_balances.read(sender) - amount);
        self.ERC20_balances.write(recipient, self.ERC20_balances.read(recipient) + amount);
        self.emit(Transfer { from: sender, to: recipient, amount: amount});
    }

    fn _spend_allowance(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
        let current_allowance = self.ERC20_allowances.read((owner, spender));
        if current_allowance != Bounded::MAX {
            _approve(ref self, owner, spender, current_allowance - amount);
        }
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

}
