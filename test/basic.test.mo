import L "../src";
import Principal "mo:base/Principal";
import Blob "mo:base/Blob";
import Float "mo:base/Float";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import I "mo:itertools/Iter";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Nat "mo:base/Nat";
import Debug "mo:base/Debug";
import Array "mo:base/Array";


actor class({ledgerId: Principal}) = this {

    private func test_subaccount(n:Nat64) : ?Blob {
        ?Blob.fromArray(Iter.toArray(I.pad<Nat8>( Iter.fromArray(ENat64(n)), 32, 0 : Nat8)));
    };

    private func ENat64(value : Nat64) : [Nat8] {
        return [
            Nat8.fromNat(Nat64.toNat(value >> 56)),
            Nat8.fromNat(Nat64.toNat((value >> 48) & 255)),
            Nat8.fromNat(Nat64.toNat((value >> 40) & 255)),
            Nat8.fromNat(Nat64.toNat((value >> 32) & 255)),
            Nat8.fromNat(Nat64.toNat((value >> 24) & 255)),
            Nat8.fromNat(Nat64.toNat((value >> 16) & 255)),
            Nat8.fromNat(Nat64.toNat((value >> 8) & 255)),
            Nat8.fromNat(Nat64.toNat(value & 255)),
        ];
    };

    var next_subaccount_id:Nat64 = 100000;

    stable let lmem = L.LMem();
    let ledger = L.Ledger<system>(lmem, Principal.toText(ledgerId), #last);
    

    let dust = 10000; // leave dust to try the balance of function

    var onSentId: Nat = 0;

    ledger.onReceive(func (t) {
        Debug.print("onReceive:"#debug_show(onSentId));
        // if (t.to.subaccount == null) {  //V: NOTNECESAARY
        //     // we will split into 1,000 subaccounts
        //     var i = 0;
        //     label sending loop {
        //         let amount = t.amount / 10000; // Each account gets 1/10000
        //         ignore ledger.send({ to = {owner=ledger.me(); subaccount=test_subaccount(Nat64.fromNat(i))}; amount; from_subaccount = t.to.subaccount; });
        //         i += 1;
        //         if (i >= 1_000) break sending;
        //     }
        // } else {
        //     // if it has subaccount
        //     // we will pass half to another subaccount
        //     if (t.amount/10 < ledger.getFee() ) return; // if we send that it will be removed from our balance but won't register
        //     ignore ledger.send({ to = {owner=ledger.me(); subaccount=test_subaccount(next_subaccount_id)}; amount = t.amount / 10 ; from_subaccount = t.to.subaccount; });
        //     next_subaccount_id += 1;
        // }
    });
    //---
    ledger.onSent(func (id:Nat64) {
        Debug.print("onSent:"#debug_show(onSentId));
        onSentId := onSentId + 1;
    });

    private func fromNat(len : Nat, n : Nat) : [Nat8] {
        let ith_byte = func(i : Nat) : Nat8 {
            assert(i < len);
            let shift : Nat = 8 * (len - 1 - i);
            Nat8.fromIntWrap(n / 2**shift)
        };
        Array.tabulate<Nat8>(len, ith_byte);
    };

    public shared ({ caller }) func sendTest(sub_nat: Nat64, amount: Nat) {
        // let sub_array: [Nat8] = fromNat(sub_nat, 32);
        // let sub_blob = Blob.fromArray(sub_array);
        //let sub_pr = Principal.fromBlob(sub_blob);
        let aux = ledger.send({ to = {owner=ledger.me();           //V: check for tokens ??????? 
                              subaccount=test_subaccount(sub_nat)}; 
                              amount = amount; 
                              from_subaccount = null; });
        Debug.print("AUX ON SENT:"#debug_show(aux));
    };

    // public shared ({ caller }) func getBlobFromNat(sub_nat: Nat) : async [Nat8] {
    //     let sub_array: [Nat8] = fromNat(sub_nat, 32);
    //     //let sub_blob = Blob.fromArray(sub_array);
    //     sub_array;
    // };

    public query func getBalanceFromNat(sub_nat: Nat64) : async Nat {
        // let sub_array: [Nat8] = fromNat(sub_nat, 32);
        // let sub_blob = Blob.fromArray(sub_array);
        // let aux:Nat = await ledger.icrc1_balance_of({owner=ledger.me();
        //                                          subaccount=test_subaccount(2)});
        let ret:Nat = ledger.balance(test_subaccount(sub_nat));                                         
        //let sub_blob = Blob.fromArray(sub_array);
        ret;
    };   
    public query func getSubFromNat(sub_nat: Nat64) : async [Nat8] {
        let ret = test_subaccount(sub_nat);//fromNat(32,sub_nat);
        let aux: Blob  = switch(ret) {
            case null "0" : Blob;
            case (?Blob) Blob;
        };
        let ret2 = Blob.toArray(aux);
        ret2;
        //let ret_array = ret.toArray();
        // let sub_blob = Blob.fromArray(sub_array);
        // let aux:Nat = await ledger.icrc1_balance_of({owner=ledger.me();
        //                                          subaccount=test_subaccount(2)});
        // let sub_array = test_subaccount(sub_nat);                                         
        // let ret = Blob.fromArray(sub_array);
        
    };   
    public query func get_onsentid() : async Nat {  
        onSentId;
    };

    public func start() {
        ledger.setOwner(Principal.fromActor(this));
        };

    public query func get_balance(s: ?Blob) : async Nat {
        ledger.balance(s)
        };

    public query func get_errors() : async [Text] {
        ledger.getErrors();
        };

    public query func get_info() : async L.Info {
        ledger.getInfo();
        };

    public query func accounts() : async [(Blob, Nat)] {
        Iter.toArray(ledger.accounts());
        };

    public query func getPending() : async Nat {
        ledger.getSender().getPendingCount();
        };
    
    public query func ver() : async Nat {
        4
        };
    
    public query func getMeta() : async L.Meta {
        ledger.getMeta()
        };

}