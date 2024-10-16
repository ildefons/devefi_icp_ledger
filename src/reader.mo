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
import List "mo:base/List";

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
        onRead : ([TxTypes.Transaction], Nat) -> ();
    }) {
        var started = false;
        let ledger = actor (Principal.toText(ledger_id)) : Ledger.Self;
        var lastTxTime : Nat64 = 0;

        var lock:Int = 0;
        let MAX_TIME_LOCKED:Int = 120_000_000_000; // 120 seconds

        private func cycle() : async () {
            if (not started) return;

            let now = Time.now();
            if (now - lock < MAX_TIME_LOCKED) return;
            lock := now;

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

            let query_start = mem.last_indexed_tx;

            let rez = await ledger.query_blocks({
                start = Nat64.fromNat(mem.last_indexed_tx);
                length = 2000*40; // later we run up to 40 queries in parallel 
            });

            if (query_start != mem.last_indexed_tx) {lock:=0; return;};

            if (rez.blocks.size()==1) {
                //Debug.print("blocksize one:"#debug_show(rez.blocks[0]));
            };
            if (rez.blocks.size()==125) {
                //Debug.print("blocksize onetwofive:"#debug_show(rez.blocks[0]));
            };


            if (rez.archived_blocks.size() == 0) {
                // We can just process the transactions that are inside the ledger and not inside archive
                //Debug.print("d1:"#debug_show(rez.blocks.size()));
                onRead(transformTransactions(rez.blocks), mem.last_indexed_tx );
                mem.last_indexed_tx += rez.blocks.size();
      
                // Set the time of the last transaction
                if (rez.blocks.size() != 0) lastTxTime := rez.blocks[rez.blocks.size() - 1].timestamp.timestamp_nanos;
           
            } else {
                // We need to collect transactions from archive and get them in order
                let unordered = Vector.new<TransactionUnordered>(); // Probably a better idea would be to use a large enough var array

                for (atx in rez.archived_blocks.vals()) {
                    
                    let args_starts = Array.tabulate<Nat>(Nat.min(40, 1 + Nat64.toNat(atx.length/2000)), func(i) = Nat64.toNat(atx.start) + i*2000);
                    let args = Array.map<Nat, Ledger.GetBlocksArgs>( args_starts, func(i) = {start = Nat64.fromNat(i); length = if (i-Nat64.toNat(atx.start):Nat+2000 <= Nat64.toNat(atx.length)) 2000 else atx.length + atx.start - Nat64.fromNat(i)  });

                    var buf = List.nil<async Ledger.ArchiveResult>();
                    var data = List.nil<Ledger.ArchiveResult>();
                    for (arg in args.vals()) {
                        // The calls are sent here without awaiting anything
                        let promise = atx.callback(arg);
                        buf := List.push(promise, buf); 
                    };

                    for (promise in List.toIter(buf)) {
                        // Await results of all promises. We recieve them in sequential order
                        data := List.push(await promise, data);
                    };
                    let chunks = List.toArray(data);
                    
                    var chunk_idx = 0;
                    for (chunk in chunks.vals()) {
                        let #Ok(txresp) = chunk else {
                            lock := 0;
                            onError("Error getting archived blocks");
                            return;
                        };
                        if (txresp.blocks.size() > 0) {
                            Vector.add(
                                unordered,
                                {
                                    start = args_starts[chunk_idx];
                                    transactions = txresp.blocks;
                                },
                            );
                        };
                        chunk_idx += 1;
                    };
                };

                let sorted = Array.sort<TransactionUnordered>(Vector.toArray(unordered), func(a, b) = Nat.compare(a.start, b.start));

                for (u in sorted.vals()) {
                    if (u.start != mem.last_indexed_tx) {
                        onError("out of order: " # Nat.toText(u.start) # " " # Nat.toText(mem.last_indexed_tx) # " " # Nat.toText(u.transactions.size()));
                        lock := 0;
                        return;
                    };//Debug.print("d2");
                    onRead(transformTransactions(u.transactions), mem.last_indexed_tx );
                    mem.last_indexed_tx += u.transactions.size();
                    if (u.transactions.size() != 0) lastTxTime := u.transactions[u.transactions.size() - 1].timestamp.timestamp_nanos;
                };

                if (rez.blocks.size() != 0) {//Debug.print("d3");
                    onRead(transformTransactions(rez.blocks), mem.last_indexed_tx );
                    mem.last_indexed_tx += rez.blocks.size();
                    lastTxTime := rez.blocks[rez.blocks.size() - 1].timestamp.timestamp_nanos;
                };
            };

            let inst_end = Prim.performanceCounter(1); // 1 is preserving with async
            onCycleEnd(inst_end - inst_start);
            lock := 0;
        };

        /// Returns the last tx time or the current time if there are no more transactions to read
        public func getReaderLastTxTime() : Nat64 { 
            lastTxTime;
        };

    
        public func start<system>() {
            if (started) Debug.trap("already started");
            started := true;
            ignore Timer.recurringTimer<system>(#seconds 2, cycle);
        };

        public func stop() {
            started := false;
        }
    };

};
