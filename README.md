# Payment Channel Smart Contract

## Overview

This Clarity smart contract implements a bidirectional payment channel system on the Stacks blockchain. Payment channels allow two parties to conduct multiple off-chain transactions with only the opening and closing transactions recorded on-chain, significantly reducing transaction costs and improving scalability.

## Key Features

- **Off-chain State Updates**: Parties can propose and confirm balance changes without on-chain transactions
- **Cryptographic Security**: All state changes require valid signatures from both parties
- **Dispute Resolution**: Challenge mechanism with timeout periods for handling conflicts
- **Cooperative Closure**: Channels can be closed instantly with mutual agreement
- **STX Token Support**: Built-in support for Stacks (STX) token transfers

## Core Components

### Data Structures

#### Payment Channels (`payment-channels` map)
- `channel-id`: Unique identifier for the channel
- `payer`: Principal who initially funded the channel
- `payee`: Principal who receives payments
- `payer-balance`: Current balance allocated to payer
- `payee-balance`: Current balance allocated to payee
- `total-balance`: Sum of both balances (constant after creation)
- `nonce`: Sequence number for state updates
- `timeout-block`: Block height for dispute resolution deadline
- `is-active`: Channel status (open/closed)

#### Channel States (`channel-states` map)
- Stores proposed state changes with signatures
- Tracks pending updates before they're finalized
- Requires signatures from both parties for execution

## Public Functions

### `open-channel`
Creates a new payment channel between two parties.

**Parameters:**
- `payee`: Principal who will receive payments
- `initial-deposit`: STX amount to deposit (from caller)

**Returns:** Channel ID on success

### `propose-state-change`
Proposes a new balance distribution within the channel.

**Parameters:**
- `channel-id`: Target channel identifier
- `nonce`: Next sequence number
- `payer-balance`: Proposed balance for payer
- `payee-balance`: Proposed balance for payee
- `signature`: Cryptographic signature proving authorization

### `confirm-state-change`
Confirms a previously proposed state change.

**Parameters:**
- `channel-id`: Target channel identifier
- `nonce`: Sequence number of the state to confirm
- `signature`: Cryptographic signature from the other party

### `close-channel`
Cooperatively closes a channel and distributes final balances.

**Parameters:**
- `channel-id`: Channel to close

### `start-challenge`
Initiates a dispute resolution process with a 24-hour timeout.

**Parameters:**
- `channel-id`: Channel to challenge

### `finalize-challenged-channel`
Finalizes a channel after the challenge timeout has expired.

**Parameters:**
- `channel-id`: Channel to finalize

## Read-Only Functions

- `get-channel`: Retrieve channel information
- `get-channel-state`: Get specific state update details
- `get-current-nonce`: Get the current sequence number for a channel

## Security Features

### Signature Validation
- All state changes require valid 65-byte ECDSA signatures
- Signatures are validated using `secp256k1-recover?`
- Both parties must sign before state changes are finalized

### Nonce System
- Sequential nonce prevents replay attacks
- Each state update must increment the nonce by exactly 1
- Prevents old state submissions

### Balance Integrity
- Total balance remains constant throughout channel lifetime
- All proposed states must sum to the original total balance
- Prevents inflation attacks

### Access Control
- Only channel participants can propose changes or close channels
- Contract validates caller identity against stored principals

## Usage Flow

1. **Channel Creation**: Payer calls `open-channel` with payee address and deposit
2. **Off-chain Transactions**: Parties exchange signed state updates
3. **State Updates**: Either party can submit `propose-state-change` on-chain
4. **Confirmation**: Other party calls `confirm-state-change` to finalize
5. **Channel Closure**: Either cooperative (`close-channel`) or disputed (`start-challenge` → `finalize-challenged-channel`)

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| u1 | ERR-ACCESS-DENIED | Unauthorized access attempt |
| u2 | ERR-ALREADY-EXISTS | Channel ID already exists |
| u3 | ERR-INVALID-AMOUNT | Invalid balance or deposit amount |
| u4 | ERR-CHANNEL-NOT-FOUND | Channel does not exist |
| u5 | ERR-CHANNEL-CLOSED | Operation on inactive channel |
| u6 | ERR-SIGNATURE-MISMATCH | Invalid signature provided |
| u7 | ERR-TIMEOUT-EXPIRED | Operation past deadline |
| u8 | ERR-INVALID-STATE | Invalid channel state |
| u9 | ERR-INSUFFICIENT-BALANCE | Insufficient STX balance |
| u10 | ERR-INVALID-UPDATE | Invalid state update |
| u11 | ERR-INVALID-PARTY | Invalid participant address |
| u12 | ERR-INVALID-NONCE | Invalid sequence number |
| u13 | ERR-INVALID-SIGNATURE | Malformed signature |

## Deployment Considerations

- Requires Stacks blockchain with Clarity smart contract support
- Contract holds STX tokens in escrow during channel lifetime
- 24-hour timeout periods for dispute resolution (1440 blocks)
- Gas costs only for channel open/close and disputed state updates

## Security Assumptions

- Both parties act rationally and monitor the blockchain
- Private keys remain secure throughout channel lifetime
- Network connectivity allows timely dispute responses
- Signatures are generated using proper cryptographic libraries