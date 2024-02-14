module {

  public type Transaction = {
    #transfer : Transfer;
    #mint : Mint;
    #burn : Burn;
    #ignored;
  };

  public type Transfer = {
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

  public type Mint = {
    to : Blob;
    amount : Nat;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

  public type Burn = {
    from : Blob;
    amount : Nat;
    spender : ?Blob;
    timestamp : Nat64;
    legacy_memo : Nat64;
    memo : ?Blob;
    created_at_time : Nat64;
  };

}