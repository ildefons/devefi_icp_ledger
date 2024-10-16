import { Principal } from '@dfinity/principal';
import { resolve } from 'node:path';
import { Actor, PocketIc, createIdentity } from '@hadronous/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE as TestService, idlFactory as TestIdlFactory, init } from './build/basic.idl.js';

import { AccountIdentifier } from "@dfinity/nns";

// import {ICRCLedgerService, ICRCLedger} from "./icrc_ledger/ledgerCanister";
import {ICPLedgerService, ICPLedger} from "./icp_ledger/ledgerCanister";
//@ts-ignore
import {toState} from "@infu/icblast";
// Jest can't handle multi threaded BigInts o.O That's why we use toState

const WASM_PATH = resolve(__dirname, "./build/basic.wasm");

export async function TestCan(pic:PocketIc, ledgerCanisterId:Principal) {
    
    const fixture = await pic.setupCanister<TestService>({
        idlFactory: TestIdlFactory,
        wasm: WASM_PATH,
        arg: IDL.encode(init({ IDL }), [{ledgerId: ledgerCanisterId}]),
    });

    return fixture;
};

describe('Basic', () => {
    let pic: PocketIc;
    let user: Actor<TestService>;
    let ledger: Actor<ICPLedgerService>;
    let userCanisterId: Principal;
    let ledgerCanisterId: Principal;

    const jo = createIdentity('superSecretAlicePassword');
    const bob = createIdentity('superSecretBobPassword');
    const ali = createIdentity('superSecretAliPassword');

    beforeAll(async () => {
      // console.log(`Jo Principal: ${jo.getPrincipal().toText()}`);
      // console.log(`Bob Principal: ${bob.getPrincipal().toText()}`);
      pic = await PocketIc.create(process.env.PIC_URL);
  
      // Ledger
      const ledgerfixture = await ICPLedger(pic, jo.getPrincipal(), pic.getSnsSubnet()?.id);
      ledger = ledgerfixture.actor;
      ledgerCanisterId = ledgerfixture.canisterId;
      
      // Ledger User
      const fixture = await TestCan(pic, ledgerCanisterId);
      user = fixture.actor;
      userCanisterId = fixture.canisterId;

      ledger.setIdentity(jo);   //ILDE: this is a pocketIC method
      await user.start();
      await passTime(100);

    });
  
    afterAll(async () => {
      await pic.tearDown();
    });
  
    it(`Check (minter) balance`  , async () => {
      const result = await ledger.icrc1_balance_of({owner: jo.getPrincipal(), subaccount: []});
      expect(toState(result)).toBe("100000000000")
    });

    // it(`Send 1 to Bob`, async () => {
    //   // ledger.setIdentity(jo);   //ILDE: this is a pocketIC method
    //   // await passTime(1000);
    //   // user.start();
      
    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: bob.getPrincipal(), subaccount:[]},
    //     from_subaccount: [],
    //     amount: 3_0000_0000n,
    //     fee: [],
    //     memo: [],
    //     created_at_time: [],
    //   });
    //   await passTime(10); //just for the debug printouts
    //   expect(toState(result)).toStrictEqual({Ok:"1"});
    // }, 6000*1000);

    // it(`Check Bob balance`  , async () => {
    //   const result = await ledger.icrc1_balance_of({owner: bob.getPrincipal(), subaccount: []});
    //   expect(toState(result)).toBe("200000000")
    // });

    // it(`Check ledger transaction log`  , async () => {
    //   const result = await ledger.query_blocks({start: 0n, length: 100n});
    //   expect(result.chain_length).toBe(2n);
    // });

    // it(`start and last_indexed_tx should be at 1`, async () => {
    //   const result2 = await user.get_info();
    //   expect(toState(result2.last_indexed_tx)).toBe("2");     
    // });

    // it(`feed ledger user and check if it made the transactions`, async () => {
   
    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[]},
    //     from_subaccount: [],
    //     amount: 1000000_0000_0000n,
    //     fee: [],
    //     memo: [],
    //     created_at_time: [],
    //   });

    //   await passTime(1200);
    //   const result2 = await user.get_info();
    //   expect(toState(result2.last_indexed_tx)).toBe("2003");
    // }, 600*1000);

    // it('Compare user<->ledger balances', async () => {
    //   let accounts = await user.accounts();
    //   let idx =0;
    //   for (let [subaccount, balance] of accounts) {
    //     idx++;
    //     if (idx % 50 != 0) continue; // check only every 50th account (to improve speed, snapshot should be enough when trying to cover all)
    //     let ledger_balance = await ledger.icrc1_balance_of({owner: userCanisterId, subaccount:[subaccount]});
    //     expect(toState(balance)).toBe(toState(ledger_balance));
    //   } 
    // }, 190*1000);

    // it('Compare user balances to snapshot', async () => {
    //   let accounts = await user.accounts();
    //   expect(toState(accounts)).toMatchSnapshot()
    // });
    
    // // it('Check if error log is empty', async () => {
    // //   let errs = await user.get_errors();
    // //   expect(toState(errs)).toStrictEqual([]);
    // // });

    it('check onSent', async () => {
      // let idbefore = await user.get_onsentid();
      // console.log("onsentid before:", idbefore);
      // const result = await ledger.icrc1_transfer({
      //   //to: {owner: userCanisterId, subaccount:[]},//to: {owner: bob.getPrincipal(), subaccount:[]},
      //   to: {owner: ali.getPrincipal(), subaccount:[]},
      //   from_subaccount: [],//[userCanisterId.toUint8Array()],//[bob.getPrincipal().toUint8Array()],//[],
      //   amount: 25_000_000n,
      //   fee: [],
      //   memo: [],
      //   created_at_time: [],
      // });
      // console.log("result:",result);
      // await passTime(10);
      // let idafter = await user.get_onsentid();
      // console.log("onsentid after:", idafter);
      //expect(toState(errs)).toStrictEqual([]);

      const result3 = await ledger.icrc1_transfer({
        to: {owner: userCanisterId, subaccount:[]},
        from_subaccount: [],
        amount: 500_0000_0000n,
        fee: [],
        memo: [],
        created_at_time: [],
      });
      await passTime(10);

      const sub_sub = await user.getSubFromNat(2n);

      await user.sendTest(2n, 123456n);
      await passTime(10);
      console.log("sub_sub:", sub_sub);
      let balance_sub1 = await ledger.icrc1_balance_of({owner: userCanisterId, subaccount:[sub_sub]});
      await passTime(10);
      console.log("balance sub1:",balance_sub1);

      const result2 = await ledger.icrc1_transfer({
        to: {owner: userCanisterId, subaccount:[sub_sub]},
        from_subaccount: [],
        amount: 5_0000_0000n,
        fee: [],
        memo: [],
        created_at_time: [],
      });

      //check balance in 2<-------------
      //const mysub = new Uint8Array([0]);//await user.getBlobFromNat(2n);
      //let balance_sub = await user.getBalanceFromNat(2n);    //<----------------WRONG: I should do ledger.getBala                                                         // I need the subaccount right
   
      console.log("sub_sub:",sub_sub);
      let balance_sub2 = await ledger.icrc1_balance_of({owner: userCanisterId, subaccount:[sub_sub]});

      await passTime(10);
      console.log("balance sub2:",balance_sub2);
    }, 600*1000);    

    async function passTime(n:number) {
      for (let i=0; i<n; i++) {
        await pic.advanceTime(3*1000);
        await pic.tick(2);
      }
    }

});
