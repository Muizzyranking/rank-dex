;; Decentralized Exchange (DEX) Smart Contract for Stacks Blockchain
;; This contract implements a constant product AMM similar to Uniswap v2

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-insufficient-liquidity (err u103))
(define-constant err-zero-amount (err u104))
(define-constant err-same-token (err u105))
(define-constant err-pool-exists (err u106))
(define-constant err-pool-not-found (err u107))
(define-constant err-slippage-exceeded (err u108))
(define-constant err-deadline-passed (err u109))
(define-constant fee-denominator u1000)
(define-constant fee-numerator u3) ;; 0.3% fee

;; Define the SIP-010 fungible token trait
(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

;; Data structures

;; Pool data - store liquidity information
(define-map pools 
  { token-x: principal, token-y: principal } ;; Composite key of the two tokens
  { 
    reserve-x: uint,
    reserve-y: uint,
    total-shares: uint,
    last-updated: uint
  }
)

;; LP token balances for liquidity providers
(define-map lp-shares
  { pool-id: { token-x: principal, token-y: principal }, provider: principal }
  { shares: uint }
)

;; Helper functions

;; Ensure token order is consistent for pool IDs
(define-private (order-tokens (token-a principal) (token-b principal))
  ;; Compare the string representation of the principals instead of using contract-of
  (if (string< (to-ascii token-a) (to-ascii token-b))
    { token-x: token-a, token-y: token-b }
    { token-x: token-b, token-y: token-a }
  )
)

;; Square root approximation for initial shares calculation
(define-private (calculate-initial-shares (amount-x uint) (amount-y uint))
  ;; Simple approximation: geometric mean
  ;; For precise math, we'd need to implement a proper square root 
  ;; But this is a reasonable approximation for initial shares
  (let
    (
      (product (* amount-x amount-y))
      ;; Take product^(1/2) using fixed iterations
      (sqrt-approx-1 (/ product u2))
      (sqrt-approx-2 (/ (+ sqrt-approx-1 (/ product sqrt-approx-1)) u2))
      (sqrt-approx-3 (/ (+ sqrt-approx-2 (/ product sqrt-approx-2)) u2))
      (sqrt-approx-4 (/ (+ sqrt-approx-3 (/ product sqrt-approx-3)) u2))
    )
    ;; Return a sensible value
    (if (> product u0)
      sqrt-approx-4
      u1) ;; Default to 1 as minimum shares
  )
)

;; Public functions

;; Create a new liquidity pool
(define-public (create-pool 
                (token-x <ft-trait>) 
                (token-y <ft-trait>) 
                (amount-x uint) 
                (amount-y uint))
  (let 
    (
      (token-x-principal (contract-of token-x))
      (token-y-principal (contract-of token-y))
      (ordered-pool-id (order-tokens token-x-principal token-y-principal))
      (initial-shares (calculate-initial-shares amount-x amount-y))
    )
    
    ;; Validate input
    (asserts! (not (is-eq token-x-principal token-y-principal)) err-same-token)
    (asserts! (> amount-x u0) err-zero-amount)
    (asserts! (> amount-y u0) err-zero-amount)
    (asserts! (is-none (map-get? pools ordered-pool-id)) err-pool-exists)
    
    ;; Transfer tokens to the contract
    (try! (contract-call? token-x transfer amount-x tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-y transfer amount-y tx-sender (as-contract tx-sender) none))
    
    ;; Create the pool
    (map-set pools ordered-pool-id {
      reserve-x: amount-x,
      reserve-y: amount-y,
      total-shares: initial-shares,
      last-updated: block-height
    })
    
    ;; Assign LP tokens to the creator
    (map-set lp-shares 
      { pool-id: ordered-pool-id, provider: tx-sender }
      { shares: initial-shares }
    )
    
    (ok initial-shares)
  )
)

;; Add liquidity to an existing pool
(define-public (add-liquidity 
                (token-x <ft-trait>) 
                (token-y <ft-trait>) 
                (amount-x uint) 
                (amount-y uint) 
                (min-shares uint)
                (deadline uint))
  (let 
    (
      (token-x-principal (contract-of token-x))
      (token-y-principal (contract-of token-y))
      (ordered-pool-id (order-tokens token-x-principal token-y-principal))
      (pool (unwrap! (map-get? pools ordered-pool-id) err-pool-not-found))
      (reserve-x (get reserve-x pool))
      (reserve-y (get reserve-y pool))
      (total-shares (get total-shares pool))
      
      ;; Calculate the optimal amounts based on the price ratio
      (optimal-y (/ (* amount-x reserve-y) reserve-x))
      (optimal-x (/ (* amount-y reserve-x) reserve-y))
      
      ;; Determine which token is limiting
      (actual-x (if (<= amount-y optimal-y) optimal-x amount-x))
      (actual-y (if (<= amount-x optimal-x) optimal-y amount-y))
      
      ;; Calculate new shares based on the proportion of liquidity added
      (new-shares (/ (* actual-x total-shares) reserve-x))
    )
    
    ;; Validate input
    (asserts! (> amount-x u0) err-zero-amount)
    (asserts! (> amount-y u0) err-zero-amount)
    (asserts! (>= new-shares min-shares) err-slippage-exceeded)
    (asserts! (< block-height deadline) err-deadline-passed)
    
    ;; Transfer tokens to the contract
    (try! (contract-call? token-x transfer actual-x tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-y transfer actual-y tx-sender (as-contract tx-sender) none))
    
    ;; Update the pool
    (map-set pools ordered-pool-id {
      reserve-x: (+ reserve-x actual-x),
      reserve-y: (+ reserve-y actual-y),
      total-shares: (+ total-shares new-shares),
      last-updated: block-height
    })
    
    ;; Update LP tokens for the provider
    (let 
      (
        (current-shares (default-to u0 (get shares (map-get? lp-shares { pool-id: ordered-pool-id, provider: tx-sender }))))
      )
      (map-set lp-shares 
        { pool-id: ordered-pool-id, provider: tx-sender }
        { shares: (+ current-shares new-shares) }
      )
    )
    
    (ok new-shares)
  )
)

;; Remove liquidity
(define-public (remove-liquidity 
                (token-x <ft-trait>) 
                (token-y <ft-trait>) 
                (shares uint)
                (min-amount-x uint)
                (min-amount-y uint)
                (deadline uint))
  (let 
    (
      (token-x-principal (contract-of token-x))
      (token-y-principal (contract-of token-y))
      (ordered-pool-id (order-tokens token-x-principal token-y-principal))
      (pool (unwrap! (map-get? pools ordered-pool-id) err-pool-not-found))
      (reserve-x (get reserve-x pool))
      (reserve-y (get reserve-y pool))
      (total-shares (get total-shares pool))
      (provider-shares-data (unwrap! (map-get? lp-shares { pool-id: ordered-pool-id, provider: tx-sender }) err-not-token-owner))
      (provider-shares (get shares provider-shares-data))
      
      ;; Calculate amounts to return based on share percentage
      (amount-x (/ (* reserve-x shares) total-shares))
      (amount-y (/ (* reserve-y shares) total-shares))
    )
    
    ;; Validate input
    (asserts! (> shares u0) err-zero-amount)
    (asserts! (>= provider-shares shares) err-insufficient-balance)
    (asserts! (>= amount-x min-amount-x) err-slippage-exceeded)
    (asserts! (>= amount-y min-amount-y) err-slippage-exceeded)
    (asserts! (< block-height deadline) err-deadline-passed)
    
    ;; Update the pool
    (map-set pools ordered-pool-id {
      reserve-x: (- reserve-x amount-x),
      reserve-y: (- reserve-y amount-y),
      total-shares: (- total-shares shares),
      last-updated: block-height
    })
    
    ;; Update LP tokens for the provider
    (map-set lp-shares 
      { pool-id: ordered-pool-id, provider: tx-sender }
      { shares: (- provider-shares shares) }
    )
    
    ;; Transfer tokens back to the provider
    (as-contract 
      (begin
        (try! (contract-call? token-x transfer amount-x (as-contract tx-sender) tx-sender none))
        (try! (contract-call? token-y transfer amount-y (as-contract tx-sender) tx-sender none))
      )
    )
    
    (ok { amount-x: amount-x, amount-y: amount-y })
  )
)

;; Swap tokens
(define-public (swap 
                (token-in <ft-trait>) 
                (token-out <ft-trait>) 
                (amount-in uint) 
                (min-amount-out uint)
                (deadline uint))
  (let 
    (
      (token-in-principal (contract-of token-in))
      (token-out-principal (contract-of token-out))
      (ordered-pool-id (order-tokens token-in-principal token-out-principal))
      (pool (unwrap! (map-get? pools ordered-pool-id) err-pool-not-found))
      
      ;; Determine which reserve is which based on token order
      (reserve-in (if (is-eq token-in-principal (get token-x ordered-pool-id)) 
                      (get reserve-x pool) 
                      (get reserve-y pool)))
      (reserve-out (if (is-eq token-out-principal (get token-x ordered-pool-id)) 
                       (get reserve-x pool) 
                       (get reserve-y pool)))
      
      ;; Calculate the swap with fees
      (amount-in-with-fee (* amount-in (- fee-denominator fee-numerator)))
      (numerator (* amount-in-with-fee reserve-out))
      (denominator (+ (* reserve-in fee-denominator) amount-in-with-fee))
      (amount-out (/ numerator denominator))
    )
    
    ;; Validate input
    (asserts! (not (is-eq token-in-principal token-out-principal)) err-same-token)
    (asserts! (> amount-in u0) err-zero-amount)
    (asserts! (>= amount-out min-amount-out) err-slippage-exceeded)
    (asserts! (< block-height deadline) err-deadline-passed)
    
    ;; Transfer token-in from user to contract
    (try! (contract-call? token-in transfer amount-in tx-sender (as-contract tx-sender) none))
    
    ;; Update reserves
    (if (is-eq token-in-principal (get token-x ordered-pool-id))
      (map-set pools ordered-pool-id {
        reserve-x: (+ reserve-in amount-in),
        reserve-y: (- reserve-out amount-out),
        total-shares: (get total-shares pool),
        last-updated: block-height
      })
      (map-set pools ordered-pool-id {
        reserve-x: (- reserve-out amount-out),
        reserve-y: (+ reserve-in amount-in),
        total-shares: (get total-shares pool),
        last-updated: block-height
      })
    )
    
    ;; Transfer token-out to user
    (as-contract
      (try! (contract-call? token-out transfer amount-out (as-contract tx-sender) tx-sender none))
    )
    
    (ok amount-out)
  )
)

;; Read-only functions

;; Get pool information
(define-read-only (get-pool (token-x principal) (token-y principal))
  (map-get? pools (order-tokens token-x token-y))
)

;; Get LP shares for a provider
(define-read-only (get-lp-shares (token-x principal) (token-y principal) (provider principal))
  (map-get? lp-shares { pool-id: (order-tokens token-x token-y), provider: provider })
)

;; Calculate the output amount for a swap
(define-read-only (get-swap-amount 
                    (token-in principal) 
                    (token-out principal) 
                    (amount-in uint))
  (let 
    (
      (ordered-pool-id (order-tokens token-in token-out))
      (pool (map-get? pools ordered-pool-id))
    )
    (match pool
      pool-data
        (let 
          (
            (reserve-in (if (is-eq token-in (get token-x ordered-pool-id)) 
                          (get reserve-x pool-data) 
                          (get reserve-y pool-data)))
            (reserve-out (if (is-eq token-out (get token-x ordered-pool-id)) 
                           (get reserve-x pool-data) 
                           (get reserve-y pool-data)))
            (amount-in-with-fee (* amount-in (- fee-denominator fee-numerator)))
            (numerator (* amount-in-with-fee reserve-out))
            (denominator (+ (* reserve-in fee-denominator) amount-in-with-fee))
          )
          (ok (/ numerator denominator))
        )
      none (err err-pool-not-found)
    )
  )
)
