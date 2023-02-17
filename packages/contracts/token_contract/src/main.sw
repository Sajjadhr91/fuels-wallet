contract;

dep errors;
dep events;
dep interface;
dep utils;

use string::String;
use std::{
    auth::{
        AuthError,
        msg_sender,
    },
    call_frames::contract_id,
    constants::{
        BASE_ASSET_ID,
        ZERO_B256,
    },
    context::msg_amount,
    logging::log,
    token::{
        burn,
        force_transfer_to_contract,
        mint_to,
        transfer,
    },
};

use errors::*;
use events::*;
use interface::Token;
use utils::{id_to_address, is_sender_owner, sender_as_address};

storage {
    owner: Option<Identity> = Option::None,
    mint_price: u64 = 0,
    mint_limit: u64 = 0,
    total_supply: u64 = 0,
    total_minted: u64 = 0,
    deposits: StorageMap<Identity, u64> = StorageMap {},
    balances: StorageMap<Identity, u64> = StorageMap {},
    allowances: StorageMap<(Identity, Identity), u64> = StorageMap {},
}

impl Token for Contract {
    #[storage(read, write)]
    fn constructor(mint_price: u64, mint_limit: u64, total_supply: u64) {
        require(storage.owner.is_some(), InitError::CannotReinitialize);
        require(total_supply != 0, InitError::AssetSupplyCannotBeZero);
        require(mint_price != 0, InitError::MintPriceCannotBeZero);
        require(mint_limit != 0, InitError::MintLimitCannotBeZero);
        let sender: Result<Identity, AuthError> = msg_sender();
        storage.owner = Option::Some(sender.unwrap());
        storage.total_supply = total_supply;
        storage.mint_price = mint_price;
        storage.mint_limit = mint_limit;
        storage.total_minted = 0;
    }

    #[storage(read)]
    fn owner() -> Identity {
        storage.owner.unwrap()
    }
    #[storage(read)]
    fn mint_limit() -> u64 {
        storage.mint_limit
    }
    #[storage(read)]
    fn mint_price() -> u64 {
        storage.mint_price
    }
    #[storage(read)]
    fn total_minted() -> u64 {
        storage.total_minted
    }
    #[storage(read)]
    fn total_supply() -> u64 {
        storage.total_supply
    }
    #[storage(read)]
    fn balance_of(address: Option<Identity>) -> u64 {
        match address.unwrap() {
            Identity::Address(addr) => {
                let sender = sender_as_address();
                let owner = id_to_address(storage.owner);
                require(sender != owner && addr != owner, AccessError::CannotQueryOwnerBalance);
                storage.balances.get(address.unwrap()) | 0
            },
            Identity::ContractId(addr) => {
                storage.balances.get(address.unwrap()) | 0
            }
        }
    }
    #[storage(read)]
    fn allowance(spender: Identity, receiver: Identity) -> u64 {
        storage.allowances.get((spender, receiver)) | 0
    }

    #[payable, storage(read, write)]
    fn mint() -> u64 {
        let sender = msg_sender().unwrap();
        require(sender != storage.owner.unwrap(), MintError::CannotMintForOwner);

        // Make deposit first
        let mint_price = storage.mint_price;
        let deposit = msg_amount();
        require(deposit > mint_price, MintError::CannotMintWithoutDeposit);
        force_transfer_to_contract(deposit, BASE_ASSET_ID, contract_id());
        storage.deposits.insert(sender, deposit);

        // Check if minting is possible
        let amount = deposit / mint_price;
        let total_plus_amount = storage.total_minted + amount;
        let curr_balance = storage.balances.get(sender) | 0;
        require(total_plus_amount <= storage.total_supply, MintError::InsufficientSupply);
        require(curr_balance + amount <= storage.mint_limit, MintError::MintLimitReached);

        // Update storage and mint tokens
        storage.balances.insert(sender, curr_balance + amount);
        storage.total_minted = total_plus_amount;
        mint_to(amount, sender);

        // Emit event
        log(MintEvent {
            to: sender,
            amount: amount,
        });

        // Return mint amount
        amount
    }

    #[storage(read, write)]
    fn approve(spender: Identity, receiver: Identity, amount: u64) -> u64 {
        let curr_allowance = storage.allowances.get((spender, receiver)) | 0;
        let balance = storage.balances.get(spender) | 0;
        require(spender != receiver, ApproveError::CannotApproveSelf);
        require(curr_allowance > amount, ApproveError::CannotApproveSameAmount);
        require(balance >= amount, ApproveError::CannotApproveMoreThanBalance);
        storage.allowances.insert((spender, receiver), amount);

        // Emit event
        log(ApprovalEvent {
            spender: spender,
            receiver: receiver,
            amount: amount,
        });

        // Return allowance amount
        amount
    }

    #[storage(read, write)]
    fn transfer_to(to: Identity, amount: u64) -> u64 {
        let sender = msg_sender().unwrap();
        _transfer(sender, to, amount)
    }

    #[storage(read, write)]
    fn transfer_from_to(from: Identity, to: Identity, amount: u64) -> u64 {
        _transfer(from, to, amount)
    }

    #[storage(read, write)]
    fn burn(amount: u64) {
        is_sender_owner(storage.owner.unwrap());

        // Require that the burn amount is less than the missing amount
        let total_minted = storage.total_minted;
        let total_supply = storage.total_supply;
        let missing_amount = total_supply - total_minted;
        require(amount <= missing_amount, BurnError::CannotBurnMoreThanMissing);
        storage.total_supply = total_supply - amount;
        burn(amount);

        // Emit event
        log(BurnEvent {
            amount: amount,
        });
    }
}

#[storage(read, write)]
fn _transfer(from: Identity, to: Identity, amount: u64) -> u64 {
    // Check if transfer is possible
    let sender = from;
    let allowance = storage.allowances.get((sender, to)) | 0;
    let curr_balance = storage.balances.get(sender) | 0;
    require(sender != to, TransferError::CannotTransferToSelf);
    require(allowance >= amount, TransferError::InsufficientAllowance);
    require(curr_balance >= amount, TransferError::InsufficientBalance);

    // Update balances of sender and receiver and transfer tokens
    let to_balance = storage.balances.get(to) | 0;
    storage.balances.insert(sender, curr_balance - amount);
    storage.balances.insert(to, to_balance + amount);
    transfer(amount, contract_id(), to);

    // Emit event
    log(TransferEvent {
        from: sender,
        to: to,
        amount: amount,
    });

    // Return transfer amount
    amount
}
