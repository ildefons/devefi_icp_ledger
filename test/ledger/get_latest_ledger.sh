#!/bin/sh
wget https://download.dfinity.systems/ic/3e25df8f16f794bc93caaefdce41467304d1b0c7/canisters/ledger-canister.wasm.gz
gunzip ledger-canister.wasm.gz


wget https://raw.githubusercontent.com/dfinity/ic/3e25df8f16f794bc93caaefdce41467304d1b0c7/rs/rosetta-api/icp_ledger/ledger.did
didc bind ledger.did -t js >ledger.idl.js