use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait IRandomProducer<TContractState> {
    fn getOwner(self: @TContractState) -> ContractAddress;
    fn getOperator(self: @TContractState) -> ContractAddress;
    fn getRandomnessRequest(self: @TContractState, request_id: u128) -> Request;
    fn requestRandom(ref self: TContractState) -> u128;
    fn fulfill(ref self: TContractState, request_id: u128, randomness: u128);
    fn setOperator(ref self: TContractState, operator: ContractAddress);
    fn setOwner(ref self: TContractState, owner: ContractAddress);
    fn setConsumer(ref self: TContractState, consumer: ContractAddress, valid: bool);
    fn upgrade(ref self: TContractState, class_hash: ClassHash);
}

#[starknet::interface]
pub trait IRandomConsumer<TContractState> {
    fn fulfillRandomness(ref self: TContractState, request_id: u128, randomness: u128);
}

#[derive(Drop, Copy, Serde, starknet::Store)]
struct Request {
    consumer: ContractAddress,
    randomness: u128,
    block_number: u64,
}

#[starknet::contract]
mod random_producer {

    use super::{IRandomProducer, IRandomConsumerDispatcher, IRandomConsumerDispatcherTrait, Request};
    use starknet::{ContractAddress, ClassHash, get_caller_address};
    use starknet::get_block_info;
    use starknet::syscalls::replace_class_syscall;
    use core::num::traits::zero::Zero;

    #[storage]
    struct Storage {
        RandomProducer_request_id_counter: u128,
        RandomProducer_requests: LegacyMap<u128, Request>,
        RandomProducer_owner: ContractAddress,
        RandomProducer_operator: ContractAddress,
        RandomProducer_consumers: LegacyMap<ContractAddress, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event{
        Upgraded: Upgraded,
    }

    #[derive(Drop, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, operator: ContractAddress) {
        self.RandomProducer_owner.write(owner);
        self.RandomProducer_operator.write(operator);
        self.RandomProducer_request_id_counter.write(1000);
    }

    #[abi(embed_v0)]
    impl RandomProducer of IRandomProducer<ContractState> {

        fn getOwner(self: @ContractState) -> ContractAddress {
            self.RandomProducer_owner.read()
        }

        fn getOperator(self: @ContractState) -> ContractAddress {
            self.RandomProducer_operator.read()
        }

        fn getRandomnessRequest(self: @ContractState, request_id: u128) -> Request {
            self.RandomProducer_requests.read(request_id)
        }

        fn requestRandom(ref self: ContractState) -> u128 {
            let caller = get_caller_address();
            let valid = self.RandomProducer_consumers.read(caller);
            assert(valid, 'invalid consumer');
            let count = self.RandomProducer_request_id_counter.read();
            let request_id = count + 1;
            self.RandomProducer_request_id_counter.write(request_id);
            self.RandomProducer_requests.write(request_id, Request{consumer: caller, randomness: 0, block_number: 0});
            request_id
        }

        fn fulfill(ref self: ContractState, request_id: u128, randomness: u128) {
            _assert_only_operator(@self);
            let mut request = self.RandomProducer_requests.read(request_id);
            assert(request.consumer.is_non_zero(), 'request not exsit');
            assert(request.block_number==0, 'request fulfilled');
            let info = get_block_info().unbox();
            request.randomness = randomness;
            request.block_number = info.block_number;
            self.RandomProducer_requests.write(request_id, request);
            IRandomConsumerDispatcher{contract_address: request.consumer}.fulfillRandomness(request_id, randomness);
        }

        fn setOperator(ref self: ContractState, operator: ContractAddress) {
            _assert_only_owner(@self);
            self.RandomProducer_operator.write(operator);
        }

        fn setOwner(ref self: ContractState, owner: ContractAddress) {
            _assert_only_owner(@self);
            self.RandomProducer_owner.write(owner);
        }

        fn setConsumer(ref self: ContractState, consumer: ContractAddress, valid: bool) {
            _assert_only_owner(@self);
            self.RandomProducer_consumers.write(consumer, valid);
        }

        fn upgrade(ref self: ContractState, class_hash: ClassHash) {
            _assert_only_owner(@self);
            replace_class_syscall(class_hash).unwrap();
            self.emit(Upgraded{class_hash: class_hash});
        }

    }

    fn _assert_only_owner(self: @ContractState) {
        let caller = get_caller_address();
        let owner = self.RandomProducer_owner.read();
        assert(owner==caller, 'caller is not owner');
    }

    fn _assert_only_operator(self: @ContractState) {
        let caller = get_caller_address();
        let owner = self.RandomProducer_operator.read();
        assert(owner==caller, 'caller is not operator');
    }

}