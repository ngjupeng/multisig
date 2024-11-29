#[starknet::contract]
mod Multisig {
    use starknet::storage::MutableVecTrait;
    use contracts::interfaces::IMultisig::{
        IMultisig, Transaction, TransactionExecuted, TransactionSigned, TransactionProposed
    };
    use contracts::interfaces::IMultisigFactory::{SupportedModules};
    use contracts::utils::{execute_calls};
    use starknet::{ContractAddress, get_caller_address};
    use starknet::{account::Call};
    use starknet::storage::{
        StoragePathEntry, Map, Vec, StoragePointerReadAccess, StoragePointerWriteAccess, VecTrait,
    };

    #[storage]
    struct Storage {
        counter: u256,
        threshold: u8,
        module: Vec<SupportedModules>,
        signers: Map<ContractAddress, bool>,
        transactions: Map<u256, Transaction>,
        transaction_calls: Map<u256, Vec<Call>>,
        transaction_signed: Map<u256, Map<ContractAddress, bool>>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TransactionProposed: TransactionProposed,
        TransactionExecuted: TransactionExecuted,
        TransactionSigned: TransactionSigned
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        signers: Array<ContractAddress>,
        threshold: u8,
        _module: Array<SupportedModules>
    ) {
        self.threshold.write(threshold);
        for module in _module {
            self.module.append().write(module);
        };
        for signer in signers {
            self.signers.write(signer, true);
        }
    }

    #[abi(embed_v0)]
    impl MultisigImpl of IMultisig<ContractState> {
        fn propose_transaction(ref self: ContractState, calls: Array<Call>) {
            // check if the caller is a signer
            let caller = get_caller_address();
            assert!(self.signers.read(caller), "Caller is not a signer");

            // increment the counter
            let new_counter = self.counter.read() + 1;
            self.counter.write(new_counter);

            // insert new pending transaction
            let transaction = Transaction { confirmations: 0, executed: false };
            self.transactions.write(new_counter, transaction);

            for call in calls {
                self.transaction_calls.entry(new_counter).append().write(call);
            };

            // emit the event
            self.emit(TransactionProposed { tx_id: new_counter, calls: calls.span() });
        }


        fn sign_transaction(ref self: ContractState, tx_id: u256) {
            // check if the caller is a signer
            let caller = get_caller_address();
            assert!(self.signers.read(caller), "Caller is not a signer");

            // check if the transaction is pending
            let mut transaction = self.transactions.read(tx_id);
            assert!(!transaction.executed, "Transaction already executed");

            // check if the caller has already signed the transaction
            let signed = self.transaction_signed.entry(tx_id).entry(caller).read();
            assert!(!signed, "Caller has already signed the transaction");

            // check current confirmations
            let confirmations = transaction.confirmations;

            // if current sign + confirmations >= threshold, execute the calls
            // if confirmations + 1 >= self.threshold.read() {
            //     transaction.executed = true;
            //     execute_calls(self.transaction_calls.entry(tx_id).into());
            //     self.emit(TransactionExecuted { tx_id: tx_id });
            // }

            // update the signed map
            self.transaction_signed.entry(tx_id).entry(caller).write(true);

            self.emit(TransactionSigned { tx_id: tx_id, signer: caller });
        }
    }
}

