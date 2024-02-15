module {

  public type Transaction = {
    #u_transfer : TransferUnprocessed;
    #u_burn : BurnUnprocessed;
    #u_mint : MintUnprocessed;
    #received : Received;
    #sent : Sent;
    #mint : Mint;
    #burn : Burn;
    #ignored;
  };

  public type TransferUnprocessed = { // Uknown yet - received or sent
    to : Blob;
    fee : Nat;
    from : Blob;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };


  public type Received = { // On canister recieve
    to : Blob;
    to_subaccount : ?Blob;
    fee : Nat;
    from : Blob;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

  public type Sent = { // Sent by canister
    to : Blob;
    from : Blob;
    from_subaccount : ?Blob;
    fee : Nat;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

  public type MintUnprocessed = { // On mint to canister
    to : Blob;
    amount : Nat;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

  public type Mint = { // On mint to canister
    to : Blob;
    to_subaccount : ?Blob;
    amount : Nat;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };


  public type BurnUnprocessed = { // On burned by canister
    from : Blob;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };


  public type Burn = { // On burned by canister
    from : Blob;
    from_subaccount : ?Blob;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

}