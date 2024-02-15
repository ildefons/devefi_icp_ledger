import fs from "fs";
import icblast, { hashIdentity, toState, initArg } from "@infu/icblast";

import { init } from "./ledger.idl.js";
import { saveCanister, loadCanister } from "./lib.js";
import { AccountIdentifier } from "@dfinity/ledger-icp";
import { Principal } from "@dfinity/principal";
let localIdentity = hashIdentity("mylocalidentity");

let me = localIdentity.getPrincipal();

let local = icblast({
  identity: localIdentity,
  local: true,
  local_host: "http://localhost:8080",
});

let aa = await local("aaaaa-aa");

let canister_id = loadCanister("ledger");
let exist = canister_id ? true : false;
// if (exist) throw "Ledger canister already exists. Can be deployed only once";

if (!canister_id) {
  let rez = await aa.provisional_create_canister_with_cycles({
    settings: {
      controllers: [me],
    },
    amount: 100000000000000,
  });

  canister_id = rez.canister_id;
  saveCanister("ledger", canister_id);
}

console.log(toState({ canister_id }));




let me_address = AccountIdentifier.fromPrincipal({
  principal: me,
  // subAccount: null,
}).toHex();

console.log(me_address);

let ledger_args = {
  Init: {
    minting_account: me_address,
    transfer_fee: {e8s:10000},
    send_whitelist: [],
    token_symbol: "tCOIN",
    token_name: "Test Coin",
    initial_values : []
  },
};

let wasm = fs.readFileSync("./ledger-canister.wasm");

await aa.install_code({
  arg: initArg(init, [ledger_args]),
  wasm_module: wasm,
  mode: { reinstall: null },
  canister_id,
});



console.log("DONE")


let ledger = await local(canister_id);
await ledger.icrc1_transfer({to:{owner:"aaaaa-aa"}, amount:1000000}).then(console.log); // making one transfer so there are not 0 in log, which usually never happens
