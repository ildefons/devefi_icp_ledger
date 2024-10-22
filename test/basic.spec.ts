import { Principal } from '@dfinity/principal';
import { resolve } from 'node:path';
import { Actor, PocketIc, createIdentity } from '@hadronous/pic';
import { IDL } from '@dfinity/candid';
import { _SERVICE as TestService, idlFactory as TestIdlFactory, init } from './build/basic.idl.js';

//import { AccountIdentifier } from "@dfinity/nns";
import { AccountIdentifier } from '@dfinity/ledger-icp';

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

    // this defines the number of subaccounts that "onreceive" send fund when it get a block to subaccount=null
    const subnum = 10n;

    // keep the last id received so we can check resends work
    let sendid = 0n;

    beforeAll(async () => {
      pic = await PocketIc.create(process.env.PIC_URL);
  
      // Ledger
      const ledgerfixture = await ICPLedger(pic, jo.getPrincipal(), pic.getSnsSubnet()?.id);
      ledger = ledgerfixture.actor;
      ledgerCanisterId = ledgerfixture.canisterId;
      
      // Ledger User
      const fixture = await TestCan(pic, ledgerCanisterId);
      user = fixture.actor;
      userCanisterId = fixture.canisterId;

      // console.log("jo:",jo.getPrincipal().toString());
      // console.log("ledger:",ledgerCanisterId.toString());
      // console.log("user:",userCanisterId.toString());

      await ledger.setIdentity(jo);   //ILDE: this is a pocketIC method

      await user.start();
      
      await passTime(100);

      // this defines the number of subaccounts that "onreceive" send fund when it get a block to subaccount=null
      await user.setNumResend(subnum);

    });
  
    afterAll(async () => {
      await pic.tearDown();
    });
  
    it(`Check (minter) balance`  , async () => {
      const result = await ledger.icrc1_balance_of({owner: jo.getPrincipal(), subaccount: []});
      expect(toState(result)).toBe("100000000000")
    });

    it(`Send some to subaccount 0 not registered`, async () => {
      
      let res = await ledger.query_blocks({start:0n,length:100n});
      console.log("res0:",res.chain_length);

      let i: bigint = 0n;
      for (; i <= subnum+subnum; i++) {
        await user.registerSubaccount(i);
      };

      const sub_sub = await user.getSubFromNat(0n);

      const result = await ledger.icrc1_transfer({
        to: {owner: userCanisterId, subaccount:[sub_sub]},
        from_subaccount: [],
        amount: 666_6666_0000n,
        fee: [],
        memo: [[1,2,3,4]],
        created_at_time: [],
      });
      await passTime(1000); //just for the debug printouts
      console.log("result:",result);
      let res1 = await ledger.query_blocks({start:0n,length:100n});
      console.log("res1:",res1.chain_length);

      let res_id = 0n; 
      if ('Ok' in result) res_id = result.Ok; 
      expect(res_id).toStrictEqual(sendid+subnum+subnum*1n); // because we are sending the first
                                                             // the null subaccount re-sends to 
      sendid = res_id;

    }, 6000*1000);

    it(`Query blocks`, async () => {
      let res = await ledger.query_blocks({start:0n,length:100n});
      console.log("res:",res.chain_length);
      await passTime(100);
    }, 6000*1000);

    it(`Send some to subaccount non-0 registered`, async () => {
      
      const sub_sub = await user.getSubFromNat(0n);

      const result = await ledger.icrc1_transfer({
        to: {owner: userCanisterId, subaccount:[sub_sub]},
        from_subaccount: [],
        amount: 766_6666_0000n,
        fee: [],
        memo: [[1,2,3,4]],
        created_at_time: [],
      });
      await passTime(1000); //just for the debug printouts
      
      let res = await ledger.query_blocks({start:0n,length:100n});
      console.log("number of blocks in ledger at the end:",res.chain_length);

      console.log("result:",result);
      let res_id = 0n; 
      if ('Ok' in result) res_id = result.Ok; 
      expect(res_id).toStrictEqual(sendid+(subnum-1n)+1n);// because = previous res_id(1) 
                                                  //            + 10 sends of previous 0
                                                  //            + 1 this test send
      sendid = res_id;
    }, 6000*1000);

    // it(`Send some to subaccount 0 resgistered`, async () => {
      
    //   const sub_sub = await user.getSubFromNat(0n);
      
    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[sub_sub]},
    //     from_subaccount: [],
    //     amount: 1666_6666_0000n,
    //     fee: [],
    //     memo: [[1,2,3,4]],
    //     created_at_time: [],
    //   });
    //   await passTime(5000); //just for the debug printouts
    //   console.log("result2:",result);

    //   let res_id = 0n; 
    //   if ('Ok' in result) res_id = result.Ok; 

    //   expect(res_id).toStrictEqual(sendid+1n+subnum); // because we are sending to 0

    //   sendid = res_id;
    // }, 6000*1000);


    // it(`Send some to subaccount non-0 resgistered`, async () => {
      
    //   const sub_sub = await user.getSubFromNat(3n);
      
    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[sub_sub]},
    //     from_subaccount: [],
    //     amount: 3666_6666_0000n,
    //     fee: [],
    //     memo: [[1,2,3,4]],
    //     created_at_time: [],
    //   });
    //   await passTime(1000); //just for the debug printouts
    //   console.log("result3:",result);

    //   let res_id = 0n; 
    //   if ('Ok' in result) res_id = result.Ok; 

    //   expect(res_id).toStrictEqual(sendid+1n+1n); // because we are sending to non-0 subaccount

    //   sendid = res_id;
    // }, 6000*1000);

    // it(`Send some to subaccount 3`, async () => {
      
    //   const sub_sub = await user.getSubFromNat(3n);
    //   await user.registerSubaccountFromBlob(sub_sub);

    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[sub_sub]},
    //     from_subaccount: [],
    //     amount: 3_3333_3333n,
    //     fee: [],
    //     memo: [[1,2,3,4]],
    //     created_at_time: [],
    //   });
    //   await passTime(1000); //just for the debug printouts
    //   console.log("result3:",result)
    //   expect(toState(result)).toStrictEqual({Ok:"3"}); //3 = 1(previous test)+1(onreceive else send)+1(this test)
    // }, 6000*1000);

    // it(`Send some to subaccount 0`, async () => { // In this case (0), onReceive replies with numResend sends
      
    //   // const sub_sub = await user.getSubFromNat(0n);
    //   // await user.registerSubaccountFromBlob(sub_sub);

    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[]},//sub_sub]},
    //     from_subaccount: [],
    //     amount: 3_3333_3333n,
    //     fee: [],
    //     memo: [[1,2,3,4]],
    //     created_at_time: [],
    //   });
    //   await passTime(1000); //just for the debug printouts
    //   console.log("result0:",result)
    //   expect(toState(result)).toStrictEqual({Ok:"3"}); //3 = 1(previous test)+1(onreceive else send)+1(this test)
    // }, 6000*1000);

    // it(`Register buaccounts`  , async () => {
    //   const subnum = 10;
      
    //   let i: bigint = 0n;

    //   for (; i <= subnum; i++) {
    //     await user.registerSubaccount(i);
    //   };

    //   const sub_sub = await user.getSubFromNat(7n);

    //   const result = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[sub_sub]},
    //     from_subaccount: [],
    //     amount: 77_7777_7777n,
    //     fee: [],
    //     memo: [[3,2,1,0]],
    //     created_at_time: [],
    //   });
    //   await passTime(1000); //just for the debug printouts
    //   console.log("result3:",result)
    
    // });

    // it(`Check Bob balance`  , async () => {
    //   const result = await ledger.icrc1_balance_of({owner: bob.getPrincipal(), subaccount: []});
    //   expect(toState(result)).toBe("212300000")
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
    //   expect(toState(result2.last_indexed_tx)).toBe("3");
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
    //   //console.log("account:", accounts);
    //   await passTime(100);
    //   let accounts2 = await user.accounts();
    //   expect(toState(accounts2)).toMatchSnapshot()
    // });
    
    // // // it('Check if error log is empty', async () => {
    // // //   let errs = await user.get_errors();
    // // //   expect(toState(errs)).toStrictEqual([]);
    // // // });

    // it('check onSent', async () => {
    //   let idbefore = await user.get_onsentid();
    //   //console.log("onsentid before:", idbefore);
    //   // const result = await ledger.icrc1_transfer({
    //   //   //to: {owner: userCanisterId, subaccount:[]},//to: {owner: bob.getPrincipal(), subaccount:[]},
    //   //   to: {owner: ali.getPrincipal(), subaccount:[]},
    //   //   from_subaccount: [],//[userCanisterId.toUint8Array()],//[bob.getPrincipal().toUint8Array()],//[],
    //   //   amount: 25_000_000n,
    //   //   fee: [],
    //   //   memo: [],
    //   //   created_at_time: [],
    //   // });
    //   // console.log("result:",result);
    //   // await passTime(10);
    //   // let idafter = await user.get_onsentid();
    //   // console.log("onsentid after:", idafter);
    //   //expect(toState(errs)).toStrictEqual([]);
      
    //   // make sure subaccount has some tokens
    //   const result3 = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[]},
    //     from_subaccount: [],
    //     amount: 500_0000_0000n,
    //     fee: [],
    //     memo: [],
    //     created_at_time: [],
    //   });
    //   await passTime(10);

    //   // send a few tokens to a subaccount so we increase setid (indicator that onsent() is executed)
    //   const sub_sub = await user.getSubFromNat(2n);
    //   await user.sendTest(2n, 123456n);
    //   await passTime(10);

    //   // console.log("sub_sub:", sub_sub);
    //   // let balance_sub1 = await ledger.icrc1_balance_of({owner: userCanisterId, subaccount:[sub_sub]});
    //   // await passTime(10);
    //   // console.log("balance sub1:",balance_sub1);

    //   const result2 = await ledger.icrc1_transfer({
    //     to: {owner: userCanisterId, subaccount:[sub_sub]},
    //     from_subaccount: [],
    //     amount: 5_0000_0000n,
    //     fee: [],
    //     memo: [],
    //     created_at_time: [],
    //   });

    //   let idafter = await user.get_onsentid();
    //   //console.log("onsentid after:", idafter);

    //   //check balance in 2<-------------
    //   //const mysub = new Uint8Array([0]);//await user.getBlobFromNat(2n);
    //   //let balance_sub = await user.getBalanceFromNat(2n);    //<----------------WRONG: I should do ledger.getBala                                                         // I need the subaccount right
   
    //   // console.log("sub_sub:",sub_sub);
    //   // let balance_sub2 = await ledger.icrc1_balance_of({owner: userCanisterId, subaccount:[sub_sub]});

    //   await passTime(10);
    //   expect(idbefore+1n).toBe(idafter)
    //   // console.log("balance sub2:",balance_sub2);
    // }, 600*1000);    

    async function passTime(n:number) {
      for (let i=0; i<n; i++) {
        await pic.advanceTime(3*1000);
        await pic.tick(2);
      }
    }

});
