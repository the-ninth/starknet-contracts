use starknet::{ContractAddress, ClassHash};

#[derive(Drop, Serde, storage_access::StorageAccess)]
struct Pentagram {
    token: ContractAddress,
    pentagram_num: u128,
    value: u256,
    status: u8,
    seed: u128,
    request_id: u128,
    hit_number: u8,
    hit_prayer_position: u8,
    expire_time: u64,
}

#[derive(Drop, Serde, storage_access::StorageAccess)]
struct PentagramPrayer {
    prayer_address: ContractAddress,
    position: u8,
    number_lower: u8,
    number_higher: u8,
}

trait ISeance<TContractState> {
    fn getPentagram(self: @TContractState, pentagram_num: u128) -> (Pentagram, Array<PentagramPrayer>);
    fn getTokenEnabled(self: @TContractState, token_address: ContractAddress) -> bool;
    fn getTokenOptionValues(self: @TContractState, token_address: ContractAddress) -> Array<u256>;
    fn getRandomProducer(self: @TContractState) -> ContractAddress;
    fn getOwner(self: @TContractState) -> ContractAddress;
    fn getOperator(self: @TContractState) -> ContractAddress;

    fn setOwner(ref self: TContractState, owner: ContractAddress);
    fn setOperator(ref self: TContractState, operator: ContractAddress);
    fn setTokenEnabled(ref self: TContractState, token_address: ContractAddress, enabled: bool);
    fn setTokenOptionValues(ref self: TContractState, token_address: ContractAddress, values: Array<u256>);
    fn pray(ref self: TContractState, token_address: ContractAddress, value: u256, pentagram_num: u128, new_pentagram_when_conflict: bool, number_lower: u8, number_higher: u8) -> u128;
    fn fulfillRandomness(ref self: TContractState, request_id: u128, randomness: u128);
    fn setRandomProducer(ref self: TContractState, random_producer: ContractAddress);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::contract]
mod seance {
    use super::{Pentagram, PentagramPrayer, ISeance};
    use array::ArrayTrait;
    use box::BoxTrait;
    use cmp::{min, max};
    use integer::{u512, u512_safe_div_rem_by_u256, u256_try_as_non_zero};
    use zeroable::{Zeroable, NonZero, IsZeroResult};
    use traits::TryInto;
    use option::OptionTrait;
    use result::ResultTrait;
    use starknet::{ContractAddress, ClassHash, get_caller_address, get_block_timestamp, get_contract_address, get_execution_info, contract_address_const};
    use starknet::syscalls::replace_class_syscall;
    use ninth::token::ierc20::{IERC20DispatcherTrait, IERC20Dispatcher};
    use ninth::random::{IRandomProducerDispatcherTrait, IRandomProducerDispatcher};

    const PentagramStatusNone: u8 = 0;
    const PentagramStatusPlaying: u8 = 1;
    const PentagramStatusDone: u8 = 2;
    const PentagramStatusEnd: u8 = 3;
    const PentagramStatusCancel: u8 = 4;
    const ExpireDuration: u64 = 3600;
    

    #[storage]
    struct Storage {
        Seance_owner: ContractAddress,
        Seance_operator: ContractAddress,
        Seance_token_option_enabled: LegacyMap<ContractAddress, bool>,
        SeanceSeance_token_option_values_length: LegacyMap<ContractAddress, usize>,
        Seance_token_option_values: LegacyMap<(ContractAddress, usize), u256>,
        Seance_pentagram_counter: u128,
        Seance_pentagrams: LegacyMap<u128, Pentagram>,
        Seance_pentagram_prayers_length: LegacyMap<u128, u8>,
        Seance_pentagram_prayers_by_position: LegacyMap<(u128, u8), PentagramPrayer>, // based on 1
        Seance_pentagram_num_by_request_id: LegacyMap<u128, u128>,
        Seance_random_producer: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event{
        Pray: Pray,
        PentagramDone: PentagramDone,
        PentagramEnd: PentagramEnd,
        Upgraded: Upgraded,
    }

    #[derive(Drop, starknet::Event)]
    struct Pray {
        pentagram_num: u128,
        token_address: ContractAddress,
        prayer_address: ContractAddress,
        value: u256,
        position: u8,
        number_lower: u8,
        number_higher: u8,
    }

    #[derive(Drop, starknet::Event)]
    struct PentagramDone {
        pentagram_num: u128,
        request_id: u128,
    }

    #[derive(Drop, starknet::Event)]
    struct PentagramEnd {
        pentagram_num: u128,
        seed: u128,
        hit_number: u8,
        hit_prayer: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, operator: ContractAddress) {
        _initializer(ref self, owner, operator);
    }

    #[external(v0)]
    impl Seance of ISeance<ContractState> {

        fn getPentagram(self: @ContractState, pentagram_num: u128) -> (Pentagram, Array<PentagramPrayer>) {
            let pentagram = self.Seance_pentagrams.read(pentagram_num);
            let prayers = _get_pentagram_prayers(self, pentagram_num);
            (pentagram, prayers)
        }

        fn getTokenEnabled(self: @ContractState, token_address: ContractAddress) -> bool {
            self.Seance_token_option_enabled.read(token_address)
        }

        fn getTokenOptionValues(self: @ContractState, token_address: ContractAddress) -> Array<u256> {
            _get_token_option_values(self, token_address)
        }

        fn getRandomProducer(self: @ContractState) -> ContractAddress {
            self.Seance_random_producer.read()
        }

        fn getOwner(self: @ContractState) -> ContractAddress {
            self.Seance_owner.read()
        }
        
        fn getOperator(self: @ContractState) -> ContractAddress {
            self.Seance_operator.read()
        }

        fn setOwner(ref self: ContractState, owner: ContractAddress) {
            _assert_only_owner(@self);
            self.Seance_owner.write(owner);
        }

        fn setOperator(ref self: ContractState, operator: ContractAddress) {
            _assert_only_owner(@self);
            self.Seance_operator.write(operator);
        }

        fn setTokenEnabled(ref self: ContractState, token_address: ContractAddress, enabled: bool) {
            _assert_only_owner(@self);
            self.Seance_token_option_enabled.write(token_address, enabled);
        }

        fn setTokenOptionValues(ref self: ContractState, token_address: ContractAddress, values: Array<u256>) {
            _assert_only_owner(@self);
            _set_token_option_values(ref self, token_address, values);
        }

        fn pray(ref self: ContractState, token_address: ContractAddress, value: u256, pentagram_num: u128, new_pentagram_when_conflict: bool, number_lower: u8, number_higher: u8) -> u128 {
            _pray(ref self, token_address, value, pentagram_num, new_pentagram_when_conflict, number_lower, number_higher)
        }
        
        fn fulfillRandomness(ref self: ContractState, request_id: u128, randomness: u128) {
            _fulfill_randomness(ref self, request_id, randomness);
        }

        fn setRandomProducer(ref self: ContractState, random_producer: ContractAddress) {
            _assert_only_owner(@self);
            self.Seance_random_producer.write(random_producer);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            _assert_only_owner(@self);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

    }

    fn _initializer(ref self: ContractState, owner: ContractAddress, operator: ContractAddress) {
        self.Seance_owner.write(owner);
        self.Seance_operator.write(operator);
    }

    fn _assert_only_owner(self: @ContractState) {
        let caller = get_caller_address();
        let owner = self.Seance_owner.read();
        assert(owner==caller, 'Seance: caller is not owner');
    }

    fn _assert_only_operator(self: @ContractState) {
        let caller = get_caller_address();
        let owner = self.Seance_operator.read();
        assert(owner==caller, 'Seance: caller is not operator');
    }

    fn _assert_token_enabled(self: @ContractState, token_address: ContractAddress) {
        let enabled = self.Seance_token_option_enabled.read(token_address);
        assert(enabled, 'Seance: token not enabled');
    }

    fn _assert_token_value_enabled(self: @ContractState, token_address: ContractAddress, value: u256) {
        let enabled = _is_token_value_enabled(self, token_address, value);
        assert(enabled, 'Seance: token value not enabled');
    }

    fn _is_token_value_enabled(self: @ContractState, token_address: ContractAddress, value: u256) -> bool {
        let mut i : usize = 0;
        let length = self.SeanceSeance_token_option_values_length.read(token_address);
        loop {
            if i == length {
                break (false);
            }
            let option_value = self.Seance_token_option_values.read((token_address, i));
            if option_value == value {
                break (true);
            }
            i += 1;
        }
    }

    fn _set_token_enabled (ref self: ContractState, token_address: ContractAddress, enabled: bool) {
        self.Seance_token_option_enabled.write(token_address, enabled);
    }

    fn _set_token_option_values(ref self: ContractState, token_address: ContractAddress, values: Array<u256>) {
        let mut i : usize = 0;
        let length = values.len();
        loop {
            if i == length {
                break ();
            }
            let value = values.at(i);
            self.Seance_token_option_values.write((token_address, i), *value);
            i += 1;
        };
        self.SeanceSeance_token_option_values_length.write(token_address, length);
    }

    fn _pray(ref self: ContractState, token_address: ContractAddress, value: u256, pentagram_num: u128, new_pentagram_when_conflict: bool,
        number_lower_arg: u8, number_higher_arg: u8,
    ) -> u128 {
        let number_lower = min(number_lower_arg, number_higher_arg);
        let number_higher = max(number_lower_arg, number_higher_arg);
        let pentagram = _findOrNewPentagram(
            ref self, token_address, pentagram_num, value, number_lower, number_higher, new_pentagram_when_conflict
        );
        let execution_info = get_execution_info().unbox();
        let caller = execution_info.caller_address;// get_caller_address();
        let this_contract = execution_info.contract_address;//get_contract_address();
        assert(IERC20Dispatcher{contract_address: token_address}.transferFrom(caller, this_contract, value), 'Seance: transfer failed');
        let length = self.Seance_pentagram_prayers_length.read(pentagram.pentagram_num);
        let position = length + 1;
        let pentagram_prayer = PentagramPrayer{
            prayer_address: caller,
            position: position,
            number_lower: number_lower,
            number_higher: number_higher,
        };
        self.Seance_pentagram_prayers_by_position.write((pentagram.pentagram_num, position), pentagram_prayer);
        self.Seance_pentagram_prayers_length.write(pentagram.pentagram_num, position);
        self.emit(
            Pray {
                pentagram_num: pentagram.pentagram_num, token_address: token_address, prayer_address: caller,
                value: value, position: position, number_lower: number_lower, number_higher: number_higher,
            }
        );
        let mut status: u8 = PentagramStatusPlaying;
        let mut request_id: u128 = 0;
        if (length == 4) {
            status = PentagramStatusDone;
            let random_producer = self.Seance_random_producer.read();
            request_id = IRandomProducerDispatcher{contract_address: random_producer}.requestRandom();
            assert(request_id!=0, 'request id is zero');
            self.Seance_pentagram_num_by_request_id.write(request_id, pentagram.pentagram_num);
            self.emit(
                PentagramDone {
                    pentagram_num: pentagram.pentagram_num, request_id: request_id,
                }
            );
        }
        let block_time = get_block_timestamp();
        let pentagramUpdated = Pentagram {
            token: pentagram.token,
            pentagram_num: pentagram.pentagram_num,
            value: pentagram.value,
            status: status,
            seed: pentagram.seed,
            request_id: request_id,
            hit_number: pentagram.hit_number,
            hit_prayer_position: pentagram.hit_prayer_position,
            expire_time: block_time + ExpireDuration,
        };
        self.Seance_pentagrams.write(pentagram.pentagram_num, pentagramUpdated);
        pentagram.pentagram_num
    }

    fn _findOrNewPentagram(ref self: ContractState, token_address: ContractAddress, pentagram_num: u128, value: u256,
        number_lower: u8, number_higher: u8, new_pentagram_when_conflict: bool
    ) -> Pentagram {
        assert(number_lower < 10 && number_higher<10 && number_lower!=number_higher, 'Seance: invalid numbers');
        
        if (pentagram_num == 0) {
            let mut pentagram_num = self.Seance_pentagram_counter.read();
            pentagram_num += 1;
            self.Seance_pentagram_counter.write(pentagram_num);
            let block_time = get_block_timestamp();
            return Pentagram {
                token: token_address, pentagram_num: pentagram_num, value: value, status: PentagramStatusPlaying, seed: 0,
                request_id: 0, hit_number: 0, hit_prayer_position: 0, expire_time: block_time + ExpireDuration
            };
        }
        let pentagram = self.Seance_pentagrams.read(pentagram_num);
        assert(pentagram.status==PentagramStatusPlaying, 'invalid pentagram status');
        assert(pentagram.value==value, 'invalid pentagram value');
        let has_conflict = _has_conflict_pray(@self, pentagram_num, number_lower, number_higher);
        assert(!has_conflict || new_pentagram_when_conflict, 'pentagram conflict');
        if (has_conflict) {
            return _new_pentagram(ref self, token_address, value);
        }
        pentagram
    }

    fn _new_pentagram(ref self: ContractState, token_address: ContractAddress, value: u256) -> Pentagram {
        _assert_token_enabled(@self, token_address);
        _assert_token_value_enabled(@self, token_address, value);
        let mut pentagram_num = self.Seance_pentagram_counter.read();
        pentagram_num += 1;
        self.Seance_pentagram_counter.write(pentagram_num);
        let block_time = get_block_timestamp();
        Pentagram {
            token: token_address, pentagram_num: pentagram_num, value: value, status: PentagramStatusPlaying, seed: 0,
            request_id: 0, hit_number: 0, hit_prayer_position: 0, expire_time: block_time + ExpireDuration
        }
    }

    fn _has_conflict_pray(self: @ContractState, pentagram_num: u128, number_lower: u8, number_higher: u8) -> bool {
        let length = self.Seance_pentagram_prayers_length.read(pentagram_num);
        let mut i = 1;
        loop {
            if i>length {
                break (false);
            }
            let pentagram_prayer = self.Seance_pentagram_prayers_by_position.read((pentagram_num, i));
            if pentagram_prayer.number_lower==number_lower || pentagram_prayer.number_lower==number_higher || pentagram_prayer.number_higher==number_lower || pentagram_prayer.number_higher==number_higher {
                break (true);
            }
            i += 1;
        }
    }

    fn _get_pentagram_prayers(self: @ContractState, pentagram_num: u128) -> Array<PentagramPrayer> {
        let length = self.Seance_pentagram_prayers_length.read(pentagram_num);
        let mut i = 1;
        let mut prayers: Array<PentagramPrayer> = ArrayTrait::new();
        loop {
            if i>length {
                break (false);
            }
            let pentagram_prayer = self.Seance_pentagram_prayers_by_position.read((pentagram_num, i));
            prayers.append(pentagram_prayer);
            i += 1;
        };
        prayers
    }

    fn _get_token_option_values(self: @ContractState, token_address: ContractAddress) -> Array<u256> {
        let length = self.SeanceSeance_token_option_values_length.read(token_address);
        let mut i = 0;
        let mut values: Array<u256> = ArrayTrait::new();
        loop {
            if i==length {
                break (false);
            }
            let value = self.Seance_token_option_values.read((token_address, i));
            values.append(value);
            i += 1;
        };
        values
    }


    // VRF will be used instead in the future
    fn _fulfill_randomness(ref self: ContractState, request_id: u128, randomness: u128) {
        let caller = get_caller_address();
        let random_producer = self.Seance_random_producer.read();
        assert(caller==random_producer, 'Seance: invalid random producer');
        let pentagram_num = self.Seance_pentagram_num_by_request_id.read(request_id);
        assert(pentagram_num!=0, 'Seance: request id missing');
        _reveal(ref self, pentagram_num, randomness);
    }

    fn _reveal(ref self: ContractState, pentagram_num: u128, seed: u128) {
        let mut pentagram = self.Seance_pentagrams.read(pentagram_num);
        assert(pentagram.status==PentagramStatusDone, 'invalid pentagram status');
        let hit_number: u8 = (seed % 10_u128).try_into().unwrap();
        let (hit_prayer, hit_prayer_position) = _find_hit_prayer(@self, pentagram_num, hit_number);
        assert(hit_prayer.is_non_zero(), 'can not find the chosen one');
        let total_value = pentagram.value * 5_u256;
        let total_value_u512: u512 = u512{limb0: total_value.low, limb1: total_value.high, limb2: 0, limb3: 0};
        let (q, _) = u512_safe_div_rem_by_u256(total_value_u512, u256_try_as_non_zero(4).unwrap());
        let distribute_value = u256{low: q.limb0, high: q.limb1};
        let mut i = 0_u8;
        loop {
            i += 1;
            if i > 5 {
                break ();
            }
            let prayer = self.Seance_pentagram_prayers_by_position.read((pentagram_num, i));
            if i==hit_prayer_position {
                continue;
            }
            IERC20Dispatcher{contract_address: pentagram.token}.transfer(prayer.prayer_address, distribute_value);
        };
        pentagram.status = PentagramStatusEnd;
        pentagram.seed = seed;
        pentagram.hit_number = hit_number;
        pentagram.hit_prayer_position = hit_prayer_position;
        self.Seance_pentagrams.write(pentagram_num, pentagram);
        self.emit(
            PentagramEnd {pentagram_num: pentagram_num, seed: seed, hit_number: hit_number, hit_prayer: hit_prayer}
        );
        return ();
    }

    fn _find_hit_prayer(self: @ContractState, pentagram_num: u128, hit_number: u8) -> (ContractAddress, u8) {
        let length = self.Seance_pentagram_prayers_length.read(pentagram_num);
        let mut i: u8 = 1;
        loop {
            if i > length {
                break (contract_address_const::<0>(), 0);
            }
            let prayer = self.Seance_pentagram_prayers_by_position.read((pentagram_num, i));
            if prayer.number_lower==hit_number || prayer.number_higher==hit_number {
                break (prayer.prayer_address, i);
            }
            i += 1;
        }
    }

}
