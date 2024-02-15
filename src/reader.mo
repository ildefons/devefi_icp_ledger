import Ledger "./icp_ledger";
import TxTypes "./txtypes";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Timer "mo:base/Timer";
import Array "mo:base/Array";
import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Vector "mo:vector";
import Debug "mo:base/Debug";
import Prim "mo:⛔";
import Nat64 "mo:base/Nat64";
import Time "mo:base/Time";
import Int "mo:base/Int";

module {
    public type Transaction = Ledger.CandidBlock;

    public type Mem = {
            var last_indexed_tx : Nat;
        };

    type TransactionUnordered = {
            start : Nat;
            transactions : [Transaction];
        };
        
    public func Mem() : Mem {
            return {
                var last_indexed_tx = 0;
            };
        };

    private func transformTransactions(bt : [Transaction]) : [TxTypes.Transaction] {
        let z = Array.map<Transaction, TxTypes.Transaction>(bt, func (b) {
            let ?op = b.transaction.operation else return #ignored; // Ignore when no operation
            let memo = b.transaction.icrc1_memo;
            let legacy_memo = b.transaction.memo;
            let created_at_time = b.transaction.created_at_time.timestamp_nanos;
            let timestamp = b.timestamp.timestamp_nanos;
            switch (op) {
                case (#Transfer({to;fee;from;amount;spender})) {
                    #u_transfer({
                        timestamp;created_at_time;legacy_memo;memo;to;fee=Nat64.toNat(fee.e8s);from;amount=Nat64.toNat(amount.e8s);spender
                    })
                };
                case (#Burn({from; amount; spender})) {
                    #u_burn({
                        timestamp;created_at_time;legacy_memo;memo;from;amount=Nat64.toNat(amount.e8s);spender
                    })
                };
                case (#Mint({to; amount})) {
                    #u_mint({
                        timestamp;created_at_time;legacy_memo;memo;to;amount=Nat64.toNat(amount.e8s)
                    })
                };
                case (_) #ignored; // Ignore approve
            }
        });
    };

    public class Reader({
        mem : Mem;
        ledger_id : Principal;
        start_from_block: {#id:Nat; #last};
        onError : (Text) -> (); // If error occurs during following and processing it will return the error
        onCycleEnd : (Nat64) -> (); // Measure performance of following and processing transactions. Returns instruction count
        onRead : [TxTypes.Transaction] -> ();
    }) {
        var started = false;
        let ledger = actor (Principal.toText(ledger_id)) : Ledger.Self;
        var lastTxTime : Nat64 = 0;

        private func cycle() : async () {
            if (not started) return;
            let inst_start = Prim.performanceCounter(1); // 1 is preserving with async

            if (mem.last_indexed_tx == 0) {
                switch(start_from_block) {
                    case (#id(id)) {
                        mem.last_indexed_tx := id;
                    };
                    case (#last) {
                        let rez = await ledger.query_blocks({
                            start = 0;
                            length = 0;
                        });
                        mem.last_indexed_tx := Nat64.toNat(rez.chain_length) -1;
                    };
                };
            };

            let rez = await ledger.query_blocks({
                start = Nat64.fromNat(mem.last_indexed_tx);
                length = 1000;
            });

            if (rez.archived_blocks.size() == 0) {
                // We can just process the transactions that are inside the ledger and not inside archive
                onRead(transformTransactions(rez.blocks));
                mem.last_indexed_tx += rez.blocks.size();
                if (rez.blocks.size() < 1000) {
                    // We have reached the end, set the last tx time to the current time
                    lastTxTime := Nat64.fromNat(Int.abs(Time.now()));
                } else {
                    // Set the time of the last transaction
                    lastTxTime := rez.blocks[rez.blocks.size() - 1].timestamp.timestamp_nanos;
                };
            } else {
                // We need to collect transactions from archive and get them in order
                let unordered = Vector.new<TransactionUnordered>(); // Probably a better idea would be to use a large enough var array

                for (atx in rez.archived_blocks.vals()) {
                    let #Ok(txresp) = await atx.callback({
                        start = atx.start;
                        length = atx.length;
                    }) else return;

                    Vector.add(
                        unordered,
                        {
                            start = Nat64.toNat(atx.start);
                            transactions = txresp.blocks;
                        },
                    );
                };

                let sorted = Array.sort<TransactionUnordered>(Vector.toArray(unordered), func(a, b) = Nat.compare(a.start, b.start));

                for (u in sorted.vals()) {
                    assert (u.start == mem.last_indexed_tx);
                    onRead(transformTransactions(u.transactions));
                    mem.last_indexed_tx += u.transactions.size();
                };

                if (rez.blocks.size() != 0) {
                    onRead(transformTransactions(rez.blocks));
                    mem.last_indexed_tx += rez.blocks.size();
                };
            };

            let inst_end = Prim.performanceCounter(1); // 1 is preserving with async
            onCycleEnd(inst_end - inst_start);
        };

        /// Returns the last tx time or the current time if there are no more transactions to read
        public func getReaderLastTxTime() : Nat64 { 
            lastTxTime;
        };

        private func cycle_shell() : async () {
            try {
                // We need it async or it won't throw errors
                await cycle();
            } catch (e) {
                onError("cycle:" # Principal.toText(ledger_id) # ":" # Error.message(e));
            };

            if (started) ignore Timer.setTimer(#seconds 2, cycle_shell);
        };

        public func start() {
            if (started) Debug.trap("already started");
            started := true;
            ignore Timer.setTimer(#seconds 2, cycle_shell);
        };

        public func stop() {
            started := false;
        }
    };

};
