import IcpReader "./reader";
import IcpSender "./sender";
import Principal "mo:base/Principal";
import Timer "mo:base/Timer";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Map "mo:map/Map";
import Blob "mo:base/Blob";
import Result "mo:base/Result";
import Option "mo:base/Option";
import ICPLedger "./icp_ledger";
import TxTypes "./txtypes";
import Debug "mo:base/Debug";
import SWB "mo:swb";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import BTree "mo:stableheapbtreemap/BTree";

module {
    type R<A,B> = Result.Result<A,B>;

    /// No other errors are currently possible
    public type SendError = {
        #InsuficientFunds;
    };

    /// Local account memory
    public type AccountMem = {
        var balance: Nat;
        var in_transit: Nat;
    };

    public type Mem = {
        reader: IcpReader.Mem;
        sender: IcpSender.Mem;
        accounts: Map.Map<Blob, AccountMem>;
        var actor_principal : ?Principal;
        known_accounts : BTree.BTree<Blob, Blob>; // account id to subaccount
        var fee : Nat;
    };

    public type Meta = {
        symbol: Text;
        decimals: Nat8;
        fee: Nat;
        minter: ICPLedger.Account;
    };

    /// Used to create new ledger memory (it's outside of the class to be able to place it in stable memory)
    public func LMem() : Mem {
        {
            reader = IcpReader.Mem();
            sender = IcpSender.Mem();
            accounts = Map.new<Blob, AccountMem>();
            var actor_principal = null;
            known_accounts = BTree.init<Blob, Blob>(?16);
            var fee = 10000;
        }
    };

    private func subaccountToBlob(s: ?Blob) : Blob {
        let ?a = s else return Blob.fromArray([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
        a;
    };


    /// Info about local ledger params returned by getInfo
    public type Info = {
        last_indexed_tx: Nat;
        accounts: Nat;
        pending: Nat;
        actor_principal: ?Principal;
        sender_instructions_cost : Nat64;
        reader_instructions_cost : Nat64;
        errors : Nat;
        lastTxTime: Nat64;
    };


    /// The ledger class
    /// start_from_block should be in most cases #last (starts from the last block when first started)
    /// if something went wrong and you need to reinstall the canister
    /// or use the library with a canister that already has tokens inside it's subaccount balances
    /// you can set start_from_block to a specific block number from which you want to start reading the ledger when reinstalled
    /// you will have to remove all onRecieve, onSent, onMint, onBurn callbacks and set them again
    /// (or they could try to make calls based on old transactions)
    /// 
    /// Example:
    /// ```motoko
    ///     stable let lmem = L.LMem();
    ///     let ledger = L.Ledger(lmem, "bnz7o-iuaaa-aaaaa-qaaaa-cai", #last);
    /// ```
    public class Ledger(lmem: Mem, ledger_id_txt: Text, start_from_block : ({#id:Nat; #last})) {

        let ledger_id = Principal.fromText(ledger_id_txt);
        var next_tx_id : Nat64 = 0;
        let errors = SWB.SlidingWindowBuffer<Text>();

        var sender_instructions_cost : Nat64 = 0;
        var reader_instructions_cost : Nat64 = 0;

        var callback_onReceive: ?((TxTypes.Received) -> ()) = null;
        var callback_onSent: ?((TxTypes.Sent) -> ()) = null;
        var callback_onMint: ?((TxTypes.Mint) -> ()) = null;
        var callback_onBurn: ?((TxTypes.Burn) -> ()) = null;
        var callback_onBalanceChange : ?((?Blob, Nat, Nat) -> ()) = null;
        // Sender 

        var started : Bool = false;

        private func logErr(e:Text) : () {
            let idx = errors.add(e);
            if ((1+idx) % 300 == 0) { // every 300 elements
                errors.delete( errors.len() - 100 ) // delete all but the last 100
            };
        };

        let icrc_sender = IcpSender.Sender({
            ledger_id;
            mem = lmem.sender;
            getFee = func () : Nat { lmem.fee };
            onError = logErr; // In case a cycle throws an error
            onConfirmations = func (confirmations: [Nat64]) {
                // handle confirmed ids after sender - not needed for now
            };
            onCycleEnd = func (i: Nat64) { sender_instructions_cost := i }; // used to measure how much instructions it takes to send transactions in one cycle
        });
        
        private func handle_incoming_amount(subaccount: ?Blob, amount: Nat) : () {
            switch(Map.get<Blob, AccountMem>(lmem.accounts, Map.bhash, subaccountToBlob(subaccount))) {
                case (?acc) {
                    acc.balance += amount:Nat;
                    ignore do ? { callback_onBalanceChange!(subaccount, acc.balance, acc.in_transit); }
                };
                case (null) {
                    Map.set(lmem.accounts, Map.bhash, subaccountToBlob(subaccount), {
                        var balance = amount;
                        var in_transit = 0;
                    });
                    ignore do ? { callback_onBalanceChange!(subaccount, amount, 0); }
                };
            };
        };

        private func handle_outgoing_amount(subaccount: ?Blob, amount: Nat) : () {
            let ?acc = Map.get(lmem.accounts, Map.bhash, subaccountToBlob(subaccount)) else return;
            acc.balance -= amount:Nat;

            // When replaying the ledger we don't have in_transit and it results in natural substraction underflow.
            // since in_transit is local and added when sending
            // we have to ignore if it when replaying
            // Also if for some reason devs decide to send funds with something else than this library, it will also be an amount that is not in transit
            if (acc.in_transit < amount) {
                acc.in_transit := 0;
            } else {
                acc.in_transit -= amount:Nat; 
            };

            if (acc.balance == 0 and acc.in_transit == 0) {
                ignore Map.remove<Blob, AccountMem>(lmem.accounts, Map.bhash, subaccountToBlob(subaccount));
            };

            ignore do ? { callback_onBalanceChange!(subaccount, acc.balance, acc.in_transit); }
        };

        let nullSubaccount:Blob = subaccountToBlob(null);
        // Usually we don't return 32 zeroes but null
        private func formatSubaccount(s: Blob) : ?Blob {
            if (s == nullSubaccount) null else ?s;
        };


        // Reader
        let icrc_reader = IcpReader.Reader({
            mem = lmem.reader;
            ledger_id;
            start_from_block;
            onError = logErr; // In case a cycle throws an error
            onCycleEnd = func (i: Nat64) { reader_instructions_cost := i }; // returns the instructions the cycle used. 
                                                        // It can include multiple calls to onRead
            onRead = func (transactions: [TxTypes.Transaction], _) {
                icrc_sender.confirm(transactions);
                
                let fee = lmem.fee;
                let ?me = lmem.actor_principal else return;
                label txloop for (tx in transactions.vals()) {
                    switch(tx) {
                        case (#u_mint(mint)) {
                            let ?subaccount = BTree.get(lmem.known_accounts, Blob.compare, mint.to) else continue txloop;
                            handle_incoming_amount(?subaccount, mint.amount);
                            ignore do ? { callback_onMint!({mint with to_subaccount = formatSubaccount(subaccount)}); };
                        };

                        case (#u_transfer(tr)) {
                            switch(BTree.get(lmem.known_accounts, Blob.compare, tr.to)) {
                                case (?subaccount) {
                                    if (tr.amount >= fee) { // ignore it since we can't even burn that
                                    handle_incoming_amount(?subaccount, tr.amount);
                                    ignore do ? { callback_onReceive!({tr with to_subaccount = formatSubaccount(subaccount)}); };
                                    }
                                };
                                case (null) ();
                            };
                      
                            switch(BTree.get(lmem.known_accounts, Blob.compare, tr.from)) {
                                case (?subaccount) {
                                    handle_outgoing_amount(?subaccount, tr.amount + fee);
                                    ignore do ? { callback_onSent!({tr with from_subaccount = formatSubaccount(subaccount)}); };
                                };
                                case (null) ();
                            };
                        };

                        case (#u_burn(burn)) {
                            let ?subaccount = BTree.get(lmem.known_accounts, Blob.compare, burn.from) else continue txloop;
                            handle_outgoing_amount(?subaccount, burn.amount + fee);
                            ignore do ? { callback_onBurn!({burn with from_subaccount = formatSubaccount(subaccount)}); };
                        };

                        case (_) continue txloop;
                    };
                 
                };
            };
        });

        icrc_sender.setGetReaderLastTxTime(icrc_reader.getReaderLastTxTime);

        private func refreshFee() : async () {
            try {
            let ledger = actor (Principal.toText(ledger_id)) : ICPLedger.Self;
            lmem.fee := await ledger.icrc1_fee();
            } catch (e) {}
        };
 
        /// The ICP ledger doesn't know all of its subaccount addresses
        /// This why we need to register them, so it can track balances and transactions
        /// Any transactions to or from a subaccount before registering it will be ignored
        public func registerSubaccount(subaccount: ?Blob) : () {
            let ?me = lmem.actor_principal else Debug.trap("no actor principal");
            ignore BTree.insert<Blob, Blob>(lmem.known_accounts, Blob.compare, Principal.toLedgerAccount(me, subaccount), subaccountToBlob(subaccount));
        };

        /// Set the actor principal. If `start` has been called before, it will really start the ledger.
        public func setOwner(act: actor {}) : () {
            lmem.actor_principal := ?Principal.fromActor(act);
        };
        

        // will loop until the actor_principal is set
        private func delayed_start<system>() : async () {
          if (not Option.isNull(lmem.actor_principal)) {
            await refreshFee();
            realStart<system>();
            ignore Timer.recurringTimer<system>(#seconds 3600, refreshFee); // every hour
          } else {
            ignore Timer.setTimer<system>(#seconds 3, delayed_start);
          }
        };

        /// Start the ledger timers
        public func start<system>() : () {
            ignore Timer.setTimer<system>(#seconds 0, delayed_start);
        };
 
        /// Really starts the ledger and the whole system
        private func realStart<system>() {
            let ?me = lmem.actor_principal else Debug.trap("no actor principal");
            Debug.print(debug_show(me));
            registerSubaccount(null);
            if (started) Debug.trap("already started");
            started := true;
            icrc_sender.start<system>(?me); // We can't call start from the constructor because this is not defined yet
            icrc_reader.start<system>();
            
        };


        /// Returns the actor principal
        public func me() : Principal {
            let ?me = lmem.actor_principal else Debug.trap("no actor principal");
            me;
        };

        /// Returns the errors that happened
        public func getErrors() : [Text] {
            let start = errors.start();
            Array.tabulate<Text>(errors.len(), func (i:Nat) {
                let ?x = errors.getOpt(start + i) else Debug.trap("memory corruption");
                x
            });
        };
    
        /// Returns info about ledger library
        public func getInfo() : Info {
            {
                last_indexed_tx = lmem.reader.last_indexed_tx;
                accounts = Map.size(lmem.accounts);
                pending = icrc_sender.getPendingCount();
                actor_principal = lmem.actor_principal;
                sent = next_tx_id;
                reader_instructions_cost;
                sender_instructions_cost;
                errors = errors.len();
                lastTxTime = icrc_reader.getReaderLastTxTime();
            }
        };

        /// Get Iter of all accounts owned by the canister (except dust < fee)
        public func accounts() : Iter.Iter<(Blob, Nat)> {
            Iter.map<(Blob, AccountMem), (Blob, Nat)>(Map.entries<Blob, AccountMem>(lmem.accounts), func((k, v)) {
                (k, v.balance - v.in_transit)
            });
        };

        let minter = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");

        /// Returns the meta of the ICP ledger
        public func getMeta() : Meta {
            { // These won't ever change for ICP except fee
                decimals = 8; 
                symbol = "ICP";
                fee = lmem.fee;
                minter = { owner=minter; subaccount = null}
            }
        };

        /// Returns the fee for sending a transaction
        public func getFee() : Nat {
            lmem.fee;
        };

        /// Returns the ledger sender class
        public func getSender() : IcpSender.Sender {
            icrc_sender;
        };

        /// Returns the ledger reader class
        public func getReader() : IcpReader.Reader {
            icrc_reader;
        };

        /// Send a transfer from a canister owned address
        /// It's added to a queue and will be sent as soon as possible.
        /// You can send tens of thousands of transactions in one update call. It just adds them to a BTree
        public func send(tr: IcpSender.TransactionInput) : R<Nat64, SendError> { // The amount we send includes the fee. meaning recepient will get the amount - fee
            let ?acc = Map.get(lmem.accounts, Map.bhash, subaccountToBlob(tr.from_subaccount)) else return #err(#InsuficientFunds);
            if (acc.balance:Nat - acc.in_transit:Nat < tr.amount) return #err(#InsuficientFunds);
            acc.in_transit += tr.amount;
            let id = next_tx_id;
            next_tx_id += 1;
            icrc_sender.send(id, tr);
            #ok(id);
        };

        /// Returns the balance of a subaccount owned by the canister (except dust < fee)
        /// It's different from the balance in the original ledger if sent transactions are not confirmed yet.
        /// We are keeping track of the in_transit amount.
        public func balance(subaccount:?Blob) : Nat {
            let ?acc = Map.get(lmem.accounts, Map.bhash, subaccountToBlob(subaccount)) else return 0;
            acc.balance - acc.in_transit;
        };

        /// Returns the internal balance in case we want to see in_transit and raw balance separately
        public func balanceInternal(subaccount:?Blob) : (Nat, Nat) {
            let ?acc = Map.get(lmem.accounts, Map.bhash, subaccountToBlob(subaccount)) else return (0,0);
            (acc.balance, acc.in_transit)
        };

        /// Called when a received transaction is confirmed. Only one function can be set. (except dust < fee)
        public func onReceive(fn:(TxTypes.Received) -> ()) : () {
            assert(Option.isNull(callback_onReceive));
            callback_onReceive := ?fn;
        };

        /// Called when a sent transaction is confirmed. Only one function can be set.
        public func onSent(fn:(TxTypes.Sent) -> ()) : () {
            assert(Option.isNull(callback_onSent));
            callback_onSent := ?fn;
        };

        /// Called when a mint transaction is received. Only one function can be set.
        /// In the rare cases when the ledger minter is sending your canister funds you need to handle this.
        /// The event won't show in onRecieve
        public func onMint(fn:(TxTypes.Mint) -> ()) : () {
            assert(Option.isNull(callback_onMint));
            callback_onMint := ?fn;
        };

        /// Called when there is a change in the balance or in_transit of a subaccount. Only one function can be set.
        /// callback input: Subaccount, balance, in_transit
        public func onBalanceChange(fn:(?Blob, Nat, Nat) -> ()) : () {
            assert(Option.isNull(callback_onBalanceChange));
            callback_onBalanceChange := ?fn;
        };

        /// Called when a burn transaction is received. Only one function can be set.
        public func onBurn(fn:(TxTypes.Burn) -> ()) : () {
            assert(Option.isNull(callback_onBurn));
            callback_onBurn := ?fn;
        };
    };


}