use starknet::ContractAddress;

#[derive(Drop, Serde)]
struct Call {
    contract_address: ContractAddress,
    entrypoint: felt252,
    calldata: Span<felt252>,
}

#[starknet::interface]
trait IMulticall<TContractState> {
    fn aggregate(self: @TContractState, calls: Array<Call>) -> Array<Span<felt252>>;
}

#[starknet::contract]
mod multicall {
    
    use starknet::SyscallResultTrait;
    use starknet::syscalls::call_contract_syscall;
    use super::{Call, IMulticall};

    #[storage]
    struct Storage {
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
    }

    #[abi(embed_v0)]
    impl Multicall of IMulticall<ContractState> {
        fn aggregate(self: @ContractState, calls: Array<Call>) -> Array<Span<felt252>> {
            let mut resp: Array<Span<felt252>> = array![];
            let mut i: usize = 0;
            let length = calls.len();
            loop {
                if i == length {
                    break;
                }
                let call = calls.at(i);
                let ret_data = call_contract_syscall(*call.contract_address, *call.entrypoint, *call.calldata).unwrap_syscall();
                resp.append(ret_data);
                i += 1;
            };
            resp
        }
    }

}