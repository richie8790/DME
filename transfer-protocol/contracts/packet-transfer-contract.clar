;; DECENTRALIZED-MESSAGE-EXCHANGE - STAGE 3
;; Implementation with comprehensive maintenance features

;; Result indicators
(define-constant RESULT-IDENTITY-NOT-FOUND u300)
(define-constant RESULT-IDENTITY-ALREADY-REGISTERED u301)
(define-constant RESULT-PERMISSION-REJECTED u302)
(define-constant RESULT-MESSAGE-NOT-FOUND u303)
(define-constant RESULT-MESSAGE-SIZE-EXCEEDED u304)
(define-constant RESULT-KEY-VERIFICATION-FAILED u305)
(define-constant RESULT-OPERATION-FAILED u306)
(define-constant RESULT-CHANNEL-NOT-FOUND u307)
(define-constant RESULT-CHANNEL-ALREADY-EXISTS u308)
(define-constant RESULT-SELF-CHANNEL-FORBIDDEN u309)
(define-constant RESULT-MESSAGE-TIMEOUT u310)
(define-constant RESULT-RESOURCE-LIMIT-REACHED u311)

;; Framework parameters
(define-constant MESSAGE-LENGTH-MAX u1024)
(define-constant ENCRYPTION-KEY-SIZE u33)
(define-constant CHANNEL-CAPACITY u100)
(define-constant STANDARD-TIMEOUT-BLOCKS u1440) ;; ~10 days (10 min blocks)

;; FRAMEWORK STATE
(define-data-var framework-admin principal tx-sender)
(define-data-var message-sequence uint u0)
(define-data-var identity-sequence uint u0)

;; DATA STRUCTURES
(define-map identity-directory principal 
  {
    active: bool,
    encryption-key: (optional (buff 33)),
    enrollment-time: uint,
    sent-count: uint,
    received-count: uint,
    recent-activity: uint
  }
)

(define-map message-ledger uint 
  {
    sender: principal,
    recipient: principal,
    encrypted-data: (buff 1024),
    timestamp-created: uint,
    received: bool,
    timestamp-received: (optional uint),
    expiration-block: uint,
    message-type: (string-utf8 20)  ;; "standard", "confidential", etc.
  }
)

(define-map identity-inbox principal (list 50 uint))

;; Authorized channels between identities
(define-map identity-channels principal (list 100 principal))

;; QUERY OPERATIONS
(define-read-only (get-identity-info (entity principal))
  (default-to 
    {
      active: false,
      encryption-key: none,
      enrollment-time: u0,
      sent-count: u0,
      received-count: u0,
      recent-activity: u0
    }
    (map-get? identity-directory entity)
  )
)

(define-read-only (is-identity-active (entity principal))
  (get active (get-identity-info entity))
)

(define-read-only (get-message-by-id (msg-id uint))
  (map-get? message-ledger msg-id)
)

(define-read-only (get-framework-stats)
  {
    total-messages: (var-get message-sequence),
    registered-identities: (var-get identity-sequence)
  }
)

(define-read-only (get-identity-inbox (entity principal))
  (default-to (list) (map-get? identity-inbox entity))
)

(define-read-only (get-message-count)
  (var-get message-sequence)
)

(define-read-only (get-identity-channels (entity principal))
  (default-to (list) (map-get? identity-channels entity))
)

;; Check if message is still valid
(define-read-only (is-message-valid (msg-id uint))
  (let (
    (message-data (unwrap! (get-message-by-id msg-id) false))
    (current-block (get-block-height))
  )
    (< current-block (get expiration-block message-data))
  )
)

;; Check if a channel exists between identities
(define-read-only (is-channel-active (source principal) (target principal))
  (let (
    (channels (get-identity-channels source))
  )
    (is-some (index-of channels target))
  )
)

;; Helper functions for block info
(define-private (get-block-time)
  (default-to u0 (get-block-info? time u0))
)

(define-private (get-block-height)
  (default-to u0 (get-block-info? id u0))
)

;; IDENTITY MANAGEMENT
(define-public (create-identity (encryption-key (buff 33)))
  (let (
    (caller tx-sender)
    (current-info (get-identity-info caller))
    (current-time (get-block-time))
  )
    ;; Verify identity doesn't already exist
    (asserts! (not (get active current-info)) 
              (err RESULT-IDENTITY-ALREADY-REGISTERED))
    
    ;; Create identity profile
    (map-set identity-directory caller
      {
        active: true,
        encryption-key: (some encryption-key),
        enrollment-time: current-time,
        sent-count: u0,
        received-count: u0,
        recent-activity: current-time
      }
    )
    
    ;; Initialize empty inbox
    (map-set identity-inbox caller (list))
    
    ;; Update counter
    (var-set identity-sequence (+ (var-get identity-sequence) u1))
    (ok true)
  )
)

(define-public (update-encryption-key (new-key (buff 33)))
  (let (
    (caller tx-sender)
    (current-info (get-identity-info caller))
    (current-time (get-block-time))
  )
    ;; Verify identity exists
    (asserts! (get active current-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    
    ;; Update key and activity timestamp
    (map-set identity-directory caller
      (merge current-info { 
        encryption-key: (some new-key),
        recent-activity: current-time
      })
    )
    
    (ok true)
  )
)

;; MESSAGING OPERATIONS
(define-public (send-message (to-identity principal) 
                          (encrypted-content (buff 1024))
                          (message-class (string-utf8 20))
                          (timeout-period uint))
  (let (
    (caller tx-sender)
    (sender-info (get-identity-info caller))
    (recipient-info (get-identity-info to-identity))
    (msg-id (var-get message-sequence))
    (current-time (get-block-time))
    (current-block (get-block-height))
    (timeout-block (if (> timeout-period u0) 
                   (+ current-block timeout-period)
                   (+ current-block STANDARD-TIMEOUT-BLOCKS)))
    (recipient-inbox (get-identity-inbox to-identity))
  )
    ;; Validate both identities exist
    (asserts! (get active sender-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    (asserts! (get active recipient-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    
    ;; Verify channel exists
    (asserts! (is-channel-active caller to-identity)
              (err RESULT-PERMISSION-REJECTED))
    
    ;; Check channel limit
    (asserts! (< (len recipient-inbox) u50)
              (err RESULT-RESOURCE-LIMIT-REACHED))
    
    ;; Store the message
    (map-set message-ledger msg-id
      {
        sender: caller,
        recipient: to-identity,
        encrypted-data: encrypted-content,
        timestamp-created: current-time,
        received: false,
        timestamp-received: none,
        expiration-block: timeout-block,
        message-type: message-class
      }
    )
    
    ;; Update recipient's inbox
    (map-set identity-inbox 
             to-identity
             (append recipient-inbox msg-id))
    
    ;; Update message counters
    (map-set identity-directory caller
      (merge sender-info { 
        sent-count: (+ (get sent-count sender-info) u1),
        recent-activity: current-time
      })
    )
    
    (map-set identity-directory to-identity
      (merge recipient-info { 
        received-count: (+ (get received-count recipient-info) u1)
      })
    )
    
    ;; Increment counter
    (var-set message-sequence (+ msg-id u1))
    
    (ok msg-id)
  )
)

(define-public (mark-received (msg-id uint))
  (let (
    (caller tx-sender)
    (message-data (unwrap! (get-message-by-id msg-id) 
                     (err RESULT-MESSAGE-NOT-FOUND)))
    (current-time (get-block-time))
    (current-block (get-block-height))
    (inbox-items (get-identity-inbox caller))
  )
    ;; Verify caller is recipient
    (asserts! (is-eq (get recipient message-data) caller) 
              (err RESULT-PERMISSION-REJECTED))
    
    ;; Check expiration
    (asserts! (< current-block (get expiration-block message-data))
              (err RESULT-MESSAGE-TIMEOUT))
    
    ;; Update receipt status
    (map-set message-ledger msg-id
      (merge message-data { 
        received: true,
        timestamp-received: (some current-time)
      })
    )
    
    ;; Remove from inbox
    (map-set identity-inbox 
             caller 
             (filter not-matching-id inbox-items))
    
    ;; Update activity timestamp
    (map-set identity-directory caller
      (merge (get-identity-info caller) { 
        recent-activity: current-time
      })
    )
    
    (ok true)
  )
)

(define-public (delete-message (msg-id uint))
  (let (
    (caller tx-sender)
    (message-data (unwrap! (get-message-by-id msg-id) 
                     (err RESULT-MESSAGE-NOT-FOUND)))
    (current-time (get-block-time))
  )
    ;; Verify caller is sender or recipient
    (asserts! (or 
               (is-eq (get sender message-data) caller)
               (is-eq (get recipient message-data) caller))
             (err RESULT-PERMISSION-REJECTED))
    
    ;; If recipient is deleting, update inbox if needed
    (if (and 
         (is-eq (get recipient message-data) caller)
         (not (get received message-data)))
        (map-set identity-inbox 
                 caller 
                 (filter not-matching-id 
                         (get-identity-inbox caller)))
        true)
    
    ;; Delete the message
    (map-delete message-ledger msg-id)
    
    ;; Update activity timestamp
    (map-set identity-directory caller
      (merge (get-identity-info caller) { 
        recent-activity: current-time
      })
    )
    
    (ok true)
  )
)

;; Helper function for filtering items
(define-private (not-matching-id (id uint))
  (not (is-eq id msg-id))
)

;; CHANNEL MANAGEMENT
(define-public (open-channel (target-identity principal))
  (let (
    (caller tx-sender)
    (caller-info (get-identity-info caller))
    (target-info (get-identity-info target-identity))
    (current-channels (get-identity-channels caller))
  )
    ;; Verify both identities exist
    (asserts! (get active caller-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    (asserts! (get active target-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    
    ;; Prevent self-channel
    (asserts! (not (is-eq caller target-identity))
              (err RESULT-SELF-CHANNEL-FORBIDDEN))
    
    ;; Check if channel already exists
    (asserts! (not (is-channel-active caller target-identity))
              (err RESULT-CHANNEL-ALREADY-EXISTS))
    
    ;; Check channel limit
    (asserts! (< (len current-channels) CHANNEL-CAPACITY)
              (err RESULT-RESOURCE-LIMIT-REACHED))
    
    ;; Add channel
    (map-set identity-channels 
             caller 
             (append current-channels target-identity))
    
    (ok true)
  )
)

(define-public (close-channel (target-identity principal))
  (let (
    (caller tx-sender)
    (current-channels (get-identity-channels caller))
  )
    ;; Check if channel exists
    (asserts! (is-channel-active caller target-identity)
              (err RESULT-CHANNEL-NOT-FOUND))
    
    ;; Remove channel
    (map-set identity-channels 
             caller 
             (filter not-matching-channel current-channels))
    
    (ok true)
  )
)

;; Helper function for filtering channels
(define-private (not-matching-channel (entity principal))
  (not (is-eq entity target-identity))
)

;; MAINTENANCE OPERATIONS
(define-public (clean-inbox)
  (let (
    (caller tx-sender)
    (inbox-items (get-identity-inbox caller))
    (current-block (get-block-height))
    (valid-inbox-items (filter is-msg-valid inbox-items))
  )
    ;; Update inbox with only valid messages
    (map-set identity-inbox caller valid-inbox-items)
    
    ;; Update activity timestamp
    (map-set identity-directory caller
      (merge (get-identity-info caller) { 
        recent-activity: (get-block-time)
      })
    )
    
    (ok true)
  )
)

;; Helper function to check if a message is valid (not expired)
(define-private (is-msg-valid (msg-id uint))
  (let (
    (msg-data (unwrap! (get-message-by-id msg-id) false))
    (current-block (get-block-height))
  )
    (if (and
         msg-data
         (< current-block (get expiration-block msg-data)))
        true
        false)
  )
)

;; Process multiple messages in batch
(define-public (batch-process-messages (msg-ids (list 20 uint)))
  (let (
    (caller tx-sender)
    (current-time (get-block-time))
  )
    ;; Verify caller is registered
    (asserts! (is-identity-active caller) 
              (err RESULT-IDENTITY-NOT-FOUND))
    
    ;; For each message in the list, process it
    ;; This is a simplified implementation that would normally
    ;; iterate through each message and perform operations
    
    ;; Update activity timestamp
    (map-set identity-directory caller
      (merge (get-identity-info caller) { 
        recent-activity: current-time
      })
    )
    
    (ok true)
  )
)

;; ADMINISTRATION FUNCTIONS
(define-public (setup-framework)
  (begin
    ;; Only admin can initialize
    (asserts! (is-eq tx-sender (var-get framework-admin)) 
              (err RESULT-PERMISSION-REJECTED))
    (ok true)
  )
)

(define-public (change-admin (new-admin principal))
  (begin
    ;; Only current admin can transfer
    (asserts! (is-eq tx-sender (var-get framework-admin)) 
              (err RESULT-PERMISSION-REJECTED))
    (var-set framework-admin new-admin)
    (ok true)
  )
)

(define-public (update-framework-config (new-timeout-period uint))
  (begin
    ;; Only admin can update settings
    (asserts! (is-eq tx-sender (var-get framework-admin)) 
              (err RESULT-PERMISSION-REJECTED))
    
    ;; Would update settings here if we had mutable framework settings
    ;; This is just a placeholder for potential future upgrades
    
    (ok true)
  )
)