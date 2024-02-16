use starknet::{ClassHash, ContractAddress, StorePacking};

#[derive(Copy, Drop, Serde)]
struct Player {
    draw_count: u32,
    win_count: u32,
}

const POW_2_32: u128 = 4294967296;

impl PlayerStorePacking of StorePacking<Player, u128> {
    fn pack(value: Player) -> u128 {
        value.draw_count.into() + (value.win_count.into() * POW_2_32)
    }

    fn unpack(value: u128) -> Player {
        Player {
            draw_count: (value & 0xffffffff).try_into().unwrap(),
            win_count: ((value / POW_2_32) & 0xffffffff).try_into().unwrap(),
        }
    }
}

#[starknet::interface]
trait IChrismasCampaign<TContractState> {
    fn timerange(self: @TContractState) -> (u64, u64);
    fn set_timerange(ref self: TContractState, start: u64, end: u64);
    fn draw(ref self: TContractState, account: ContractAddress);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
    fn set_day_limit(ref self: TContractState, day_limit: u32);
}

#[starknet::contract]
mod chrismas {
    use openzeppelin::access::accesscontrol::accesscontrol::AccessControlComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::upgrades::upgradeable::UpgradeableComponent;
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_block_timestamp};
    use poseidon::poseidon_hash_span;
    use super::{Player, IChrismasCampaign};
    use ninth::token::erc1155_burnable::{IERC1155BurnableDispatcher, IERC1155BurnableDispatcherTrait};

    const RoleDefaultAdmin: felt252 = 0x0;
    const RoleUpgrader: felt252 = 0x03379fed69cc4e9195268d1965dba8d62246cc1c0e42695417a69664b0f7ff5;
    const RoleAdmin: felt252 = 0xaffd781351ea8ad3cd67f64a8ffa5919206623ec343d2583ab317bb5bd2b82;
    const RoleDrawer: felt252 = 0x0292e4875946f86644133dc8cd981b05d91be20a50589662a94211c06139ed87;

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
        Draw: Draw,
        AccessControlEvent: AccessControlComponent::Event,
        SRC5Event: SRC5Component::Event,
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Draw {
        player: ContractAddress,
        contract: ContractAddress,
        draw_count: u32,
        won: bool,
    }

    #[storage]
    struct Storage {
        players: LegacyMap<ContractAddress, Player>,
        day_limit: u32,
        day_count: LegacyMap<u32, u32>,
        mintable_erc1155: IERC1155BurnableDispatcher,
        erc1155_id: u256,
        start_time: u64,
        end_time: u64,

        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, mintable_erc1155: IERC1155BurnableDispatcher, erc1155_id: u256, day_limit: u32) {
        self.accesscontrol._grant_role(RoleDefaultAdmin, owner);
        self.accesscontrol._grant_role(RoleAdmin, owner);
        self.mintable_erc1155.write(mintable_erc1155);
        self.erc1155_id.write(erc1155_id);
        self.day_limit.write(day_limit);
    }

    #[external(v0)]
    impl ChrismasCampaign of IChrismasCampaign<ContractState> {
        fn timerange(self: @ContractState) -> (u64, u64) {
            (self.start_time.read(), self.end_time.read())
        }

        fn draw(ref self: ContractState, account: ContractAddress) {
            let block_timestamp = get_block_timestamp();
            if block_timestamp < self.start_time.read() || block_timestamp > self.end_time.read() {
                return;
            }
            self.accesscontrol.assert_only_role(RoleDrawer);
            let caller = get_caller_address();
            let day_index = self._get_day_index(block_timestamp);
            let day_count = self.day_count.read(day_index);
            let day_limit = self.day_limit.read();
            if day_count >= day_limit {
                return;
            }
            let mut player = self.players.read(account);
            player.draw_count += 1;
            // unsafe random
            let mut salts: Array<felt252> = array![];
            salts.append(caller.into());
            salts.append(account.into());
            salts.append(player.draw_count.into());
            salts.append(0xff11ff17a1d6a83094c327e);
            let num: u256 = poseidon_hash_span(salts.span()).into();
            let mut won = false;
            if num % 50 < 1 {
                let mintable_erc1155 = self.mintable_erc1155.read();
                let erc1155_id = self.erc1155_id.read();
                mintable_erc1155.mint(account, erc1155_id, 1);
                player.win_count += 1;
                won = true;
                self.day_count.write(day_index, day_count + 1);
            }
            self.players.write(account, player);
            self.emit(Draw{player: account, contract: caller, draw_count: player.draw_count, won});
        }

        fn set_timerange(ref self: ContractState, start: u64, end: u64) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            self.start_time.write(start);
            self.end_time.write(end);
        }

        fn set_day_limit(ref self: ContractState, day_limit: u32) {
            self.accesscontrol.assert_only_role(RoleAdmin);
            self.day_limit.write(day_limit);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(RoleUpgrader);
            self.upgradeable._upgrade(class_hash);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_day_index(self: @ContractState, timestamp: u64) -> u32 {
            (timestamp / 86400).try_into().unwrap() + 1
        }
    }

}