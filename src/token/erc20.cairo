use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IUpgrade<TContractState> {
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::contract]
mod ERC20 {
    use ninth::erc::ierc20::IERC20;
    use ninth::token::imintable::IMintable;
    use integer::BoundedInt;
    use zeroable::Zeroable;
    use result::ResultTrait;
    use starknet::{ContractAddress, ClassHash};
    use starknet::{get_caller_address};
    use starknet::syscalls::replace_class_syscall;
    

    #[storage]
    struct Storage {
        ERC20_name: felt252,
        ERC20_symbol: felt252,
        ERC20_decimals: u8,
        ERC20_total_supply: u256,
        ERC20_balances: LegacyMap<ContractAddress, u256>,
        ERC20_allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
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

    #[constructor]
    fn constructor(
        ref self: ContractState, name: felt252, symbol: felt252, decimals: u8, initial_supply: u256, recipient: ContractAddress
    ) {
        initializer(ref self, name, symbol, decimals);
        _mint(ref self, recipient, initial_supply);
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
            _mint(ref self, to, amount);
        }
    }

    #[abi(embed_v0)]
    impl Upgrade of super::IUpgrade<ContractState> {
        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            replace_class_syscall(class_hash).unwrap();
        }
    }

    fn initializer(ref self: ContractState, name_: felt252, symbol_: felt252, decimals_: u8) {
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
        self.emit(Transfer { from: Zeroable::zero(), to: recipient, amount: amount});
    }

    fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
        assert(!account.is_zero(), 'ERC20: burn from 0');
        self.ERC20_total_supply.write(self.ERC20_total_supply.read() - amount);
        self.ERC20_balances.write(account, self.ERC20_balances.read(account) - amount);
        self.emit(Transfer { from: account, to: Zeroable::zero(), amount: amount});
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
        if current_allowance != BoundedInt::max() {
            _approve(ref self, owner, spender, current_allowance - amount);
        }
    }

}
