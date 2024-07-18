use starknet::{ClassHash, ContractAddress, StorePacking};

#[starknet::interface]
trait IWhitelistMint<TContractState> {
    fn get_whitelist(self: @TContractState, account: ContractAddress, token_id: u256) -> Whitelist;
    fn set_whitelist(ref self: TContractState, account: ContractAddress, token_id: u256, total_mintable: u32);
    fn add_whitelist(ref self: TContractState, account: ContractAddress, token_id: u256, mintable: u32);
    fn mint(ref self: TContractState, token_id: u256);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[derive(Copy, Drop, Serde)]
struct Whitelist {
    total_mintable: u32,
    minted_count: u32,
}

const POW_2_32: u128 = 4294967296;

impl WhitelistPacking of StorePacking<Whitelist, u128> {
    fn pack(value: Whitelist) -> u128 {
        value.total_mintable.into() + (value.minted_count.into() * POW_2_32)
    }

    fn unpack(value: u128) -> Whitelist {
        Whitelist {
            total_mintable: (value & 0xffffffff).try_into().unwrap(),
            minted_count: ((value / POW_2_32) & 0xffffffff).try_into().unwrap(),
        }
    }
}

#[starknet::contract]
mod whitelist_mint {
    use openzeppelin::access::accesscontrol::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_block_timestamp};
    use poseidon::poseidon_hash_span;
    use super::{IWhitelistMint, Whitelist};
    use ninth::token::erc1155_burnable::{IERC1155BurnableDispatcher, IERC1155BurnableDispatcherTrait};

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;
    const RoleAdmin: felt252 = 0xaffd781351ea8ad3cd67f64a8ffa5919206623ec343d2583ab317bb5bd2b82;

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Mint: Mint,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Mint {
        account: ContractAddress,
        token_id: u256,
        value: u256,
    }

    #[storage]
    struct Storage {
        available_mint: LegacyMap<(ContractAddress, u256), Whitelist>, // <(player, erc1155 contract, token id), total_mintable>
        mintable_erc1155: IERC1155BurnableDispatcher,
        
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, mintable_erc1155: IERC1155BurnableDispatcher) {
        self.accesscontrol._grant_role(RoleDefaultAdmin, owner);
        self.accesscontrol._grant_role(RoleAdmin, owner);
        self.mintable_erc1155.write(mintable_erc1155);
    }

    #[abi(embed_v0)]
    impl WhitelistMintImpl of IWhitelistMint<ContractState> {
        fn get_whitelist(self: @ContractState, account: ContractAddress, token_id: u256) -> Whitelist {
            self.available_mint.read((account, token_id))
        }
        
        fn set_whitelist(ref self: ContractState, account: ContractAddress, token_id: u256, total_mintable: u32) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            let mut whitelist = self.available_mint.read((account, token_id));
            whitelist.total_mintable = total_mintable;
            self.available_mint.write((account, token_id), whitelist);
        }

        fn add_whitelist(ref self: ContractState, account: ContractAddress, token_id: u256, mintable: u32) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            let mut whitelist = self.available_mint.read((account, token_id));
            whitelist.total_mintable += mintable;
            self.available_mint.write((account, token_id), whitelist);
        }

        fn mint(ref self: ContractState, token_id: u256) {
            let account = get_caller_address();
            let mut whitelist = self.available_mint.read((account, token_id));
            assert(whitelist.total_mintable > whitelist.minted_count, 'not enough mintable tokens');
            whitelist.minted_count += 1;
            self.available_mint.write((account, token_id), whitelist);
            let mintable_erc1155 = self.mintable_erc1155.read();
            mintable_erc1155.mint(account, token_id, 1);
            self.emit(Mint{account, token_id, value: 1});
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(RoleUpgrader);
            self.upgradeable.upgrade(class_hash);
        }
    }

}