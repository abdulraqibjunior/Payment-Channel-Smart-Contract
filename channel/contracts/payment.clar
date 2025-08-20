;; Constants 
(define-constant ERR-ACCESS-DENIED (err u1))
(define-constant ERR-ALREADY-EXISTS (err u2))
(define-constant ERR-INVALID-AMOUNT (err u3))
(define-constant ERR-CHANNEL-NOT-FOUND (err u4))
(define-constant ERR-CHANNEL-CLOSED (err u5))
(define-constant ERR-SIGNATURE-MISMATCH (err u6))
(define-constant ERR-TIMEOUT-EXPIRED (err u7))
(define-constant ERR-INVALID-STATE (err u8))
(define-constant ERR-INSUFFICIENT-BALANCE (err u9))
(define-constant ERR-INVALID-UPDATE (err u10))
(define-constant ERR-INVALID-PARTY (err u11))
(define-constant ERR-INVALID-NONCE (err u12))
(define-constant ERR-INVALID-SIGNATURE (err u13))

;; Data Variables
(define-map payment-channels
  { channel-id: uint }
  {
    payer: principal,
    payee: principal,
    payer-balance: uint,
    payee-balance: uint,
    total-balance: uint,
    nonce: uint,
    timeout-block: uint,
    is-active: bool
  })

(define-data-var next-channel-id uint u0)

(define-map channel-states
  { 
    channel-id: uint,
    nonce: uint 
  }
  {
    payer-balance: uint,
    payee-balance: uint,
    payer-signature: (optional (buff 65)),
    payee-signature: (optional (buff 65))
  })

  ;; Read-only functions
  (define-read-only (get-channel (channel-id uint))
    (map-get? payment-channels { channel-id: channel-id }))

  (define-read-only (get-channel-state (channel-id uint) (nonce uint))
    (map-get? channel-states { channel-id: channel-id, nonce: nonce }))

  (define-read-only (get-current-nonce (channel-id uint))
    (match (get-channel channel-id)
      channel (get nonce channel)
      u0))

  ;; Private helper functions
  (define-private (is-valid-signature (sig (buff 65)))
    (and 
      (is-eq (len sig) u65)
      (is-ok (secp256k1-recover? 0x0000000000000000000000000000000000000000000000000000000000000000 sig))))

  (define-private (is-valid-nonce (channel-id uint) (nonce uint))
    (match (get-channel channel-id)
      channel (is-eq nonce (+ (get nonce channel) u1))
      false))

  (define-private (validate-party (party principal))
    (and 
      (not (is-eq party tx-sender))
      (not (is-eq party (as-contract tx-sender)))))

      ;; Public functions
      (define-public (open-channel (payee principal) (initial-deposit uint))
        (let
          ((channel-id (var-get next-channel-id))
           (sender tx-sender))

          ;; Validate payee principal
          (asserts! (validate-party payee) ERR-INVALID-PARTY)

          ;; Standard checks
          (asserts! (> initial-deposit u0) ERR-INVALID-AMOUNT)
          (asserts! (is-none (get-channel channel-id)) ERR-ALREADY-EXISTS)
          (asserts! (>= (stx-get-balance sender) initial-deposit) ERR-INSUFFICIENT-BALANCE)

          ;; Transfer deposit to contract
          (try! (stx-transfer? initial-deposit sender (as-contract tx-sender)))

          ;; Create channel
          (map-set payment-channels
            { channel-id: channel-id }
            {
              payer: sender,
              payee: payee,
              payer-balance: initial-deposit,
              payee-balance: u0,
              total-balance: initial-deposit,
              nonce: u0,
              timeout-block: (+ block-height u1440), ;; 24 hour timeout
              is-active: true
            })

          ;; Store initial state
          (map-set channel-states
            { channel-id: channel-id, nonce: u0 }
            {
              payer-balance: initial-deposit,
              payee-balance: u0,
              payer-signature: none,
              payee-signature: none
            })

          ;; Increment channel ID
          (var-set next-channel-id (+ channel-id u1))
          (ok channel-id)))

(define-public (propose-state-change
    (channel-id uint)
    (nonce uint)
    (payer-balance uint)
    (payee-balance uint)
    (signature (buff 65)))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND))
     (sender tx-sender))

    ;; Validate signature
    (asserts! (is-valid-signature signature) ERR-INVALID-SIGNATURE)

    ;; Validate nonce
    (asserts! (is-valid-nonce channel-id nonce) ERR-INVALID-NONCE)

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify balances match total balance
    (asserts! (is-eq (+ payer-balance payee-balance) 
                     (get total-balance channel)) ERR-INVALID-AMOUNT)

    ;; Store proposed state with signature
    (map-set channel-states
      { channel-id: channel-id, nonce: nonce }
      {
        payer-balance: payer-balance,
        payee-balance: payee-balance,
        payer-signature: (if (is-eq sender (get payer channel)) 
                     (some signature)
                     none),
        payee-signature: (if (is-eq sender (get payee channel))
                     (some signature)
                     none)
      })
    (ok true)))

(define-public (confirm-state-change
    (channel-id uint)
    (nonce uint)
    (signature (buff 65)))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND))
     (state (unwrap! (get-channel-state channel-id nonce) ERR-INVALID-STATE))
     (sender tx-sender))

    ;; Validate signature and nonce
    (asserts! (is-valid-signature signature) ERR-INVALID-SIGNATURE)
    (asserts! (is-valid-nonce channel-id nonce) ERR-INVALID-NONCE)

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Update signatures based on sender
    (if (is-eq sender (get payer channel))
      (map-set channel-states
        { channel-id: channel-id, nonce: nonce }
        (merge state { payer-signature: (some signature) }))
      (map-set channel-states
        { channel-id: channel-id, nonce: nonce }
        (merge state { payee-signature: (some signature) })))

    ;; Check if both signatures are present
    (let ((updated-state (unwrap! (get-channel-state channel-id nonce) ERR-INVALID-STATE)))
      (match (get payer-signature updated-state)
        payer-sig 
        (match (get payee-signature updated-state)
          payee-sig
          (begin
            ;; Update channel state
            (map-set payment-channels
              { channel-id: channel-id }
              (merge channel {
                payer-balance: (get payer-balance updated-state),
                payee-balance: (get payee-balance updated-state),
                nonce: nonce
              }))
            (ok true))
          ERR-INVALID-STATE)
        ERR-INVALID-STATE))))

(define-public (close-channel (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify caller is participant
    (asserts! (or
                (is-eq tx-sender (get payer channel))
                (is-eq tx-sender (get payee channel)))
              ERR-ACCESS-DENIED)

    ;; Transfer balances
    (try! (as-contract 
      (stx-transfer? (get payer-balance channel) tx-sender (get payer channel))))
    (try! (as-contract 
      (stx-transfer? (get payee-balance channel) tx-sender (get payee channel))))

    ;; Close channel
    (map-set payment-channels
      { channel-id: channel-id }
      (merge channel { is-active: false }))
    (ok true)))

(define-public (start-challenge (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify caller is participant
    (asserts! (or
                (is-eq tx-sender (get payer channel))
                (is-eq tx-sender (get payee channel)))
              ERR-ACCESS-DENIED)

    ;; Set challenge timeout
    (map-set payment-channels
      { channel-id: channel-id }
      (merge channel
        {
          timeout-block: (+ block-height u1440) ;; 24 hour challenge period
        }))
    (ok true)))

(define-public (finalize-challenged-channel (channel-id uint))
  (let
    ((channel (unwrap! (get-channel channel-id) ERR-CHANNEL-NOT-FOUND)))

    ;; Verify channel is active
    (asserts! (get is-active channel) ERR-CHANNEL-CLOSED)

    ;; Verify timeout has passed
    (asserts! (>= block-height (get timeout-block channel))
              ERR-INVALID-STATE)

    ;; Transfer balances
    (try! (as-contract 
      (stx-transfer? (get payer-balance channel) tx-sender (get payer channel))))
    (try! (as-contract 
      (stx-transfer? (get payee-balance channel) tx-sender (get payee channel))))

    ;; Close channel
    (map-set payment-channels
      { channel-id: channel-id }
      (merge channel { is-active: false }))
    (ok true)))