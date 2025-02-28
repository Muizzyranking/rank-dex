# Stacks DEX - Decentralized Exchange

## Overview

Stacks DEX is a decentralized exchange built on the Stacks blockchain, implementing an automated market maker (AMM) model similar to Uniswap v2. This protocol enables permissionless token swaps, liquidity provision, and yield generation for Stacks token holders.

## Features

- **Automated Market Maker (AMM)**: Uses a constant product formula (x * y = k) to determine token prices.
- **Liquidity Pools**: Users can create and contribute to liquidity pools of any SIP-010 compliant token pairs.
- **Token Swaps**: Enables trustless exchange between any SIP-010 compliant tokens.
- **Liquidity Provider Rewards**: Liquidity providers earn a 0.3% fee from all trades proportional to their share of the pool.
- **Slippage Protection**: Includes minimum output and deadline parameters to protect users from front-running and price movements.

## Technical Details

### Smart Contract Architecture

The core of the DEX is a single Clarity smart contract that manages:

- Pool creation and management
- Liquidity provision and withdrawal
- Token swapping mechanism
- Fee collection and distribution

### Key Functions

- **create-pool**: Initialize a new liquidity pool for a token pair
- **add-liquidity**: Add tokens to an existing pool and receive LP shares
- **remove-liquidity**: Burn LP shares and withdraw tokens
- **swap**: Exchange one token for another using the AMM formula
- **get-swap-amount**: Calculate the expected output amount for a swap (read-only)

### Fee Structure

- 0.3% trading fee on all swaps
- 100% of fees are distributed to liquidity providers

## Security Considerations

- **Slippage Protection**: All trading functions include minimum output parameters to protect against front-running.
- **Deadline Parameters**: Transactions can specify a block height deadline after which they will fail, preventing stale trades.
- **Consistent Token Ordering**: Token pairs are consistently ordered regardless of the order they're provided in function calls.

## Mathematical Model

The DEX uses the constant product formula:

```
x * y = k
```

Where:
- x is the reserve of token X
- y is the reserve of token Y
- k is a constant that only changes when liquidity is added or removed

For a swap with a 0.3% fee, the output amount is calculated as:

```
amount_out = (amount_in * 0.997 * reserve_out) / (reserve_in + amount_in * 0.997)
```

## Limitations

- The contract uses a simple square root approximation for initial shares calculation.
- Price oracle functionality is not implemented in this version.
- Flash loans are not supported.

## Integration

This contract follows the SIP-010 fungible token standard for Stacks, making it compatible with any compliant token.
