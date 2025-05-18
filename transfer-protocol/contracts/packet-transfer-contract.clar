;; DECENTRALIZED-MESSAGE-EXCHANGE - STAGE 1
;; Basic implementation with core identity and messaging features

;; Result indicators
(define-constant RESULT-IDENTITY-NOT-FOUND u300)
(define-constant RESULT-IDENTITY-ALREADY-REGISTERED u301)
(define-constant RESULT-PERMISSION-REJECTED u302)
(define-constant RESULT-MESSAGE-NOT-FOUND u303)
(define-constant RESULT-MESSAGE-SIZE-EXCEEDED u304)

;; Framework parameters
(define-constant MESSAGE-LENGTH-MAX u1024)
(define-constant ENCRYPTION-KEY-SIZE u33)

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
    timestamp-received: (optional uint)
  }
)

(define-map identity-inbox principal (list 50 uint))

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

;; Helper functions for block info
(define-private (get-block-time)
  (default-to u0 (get-block-info? time u0))
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
(define-public (send-message (to-identity principal) (encrypted-content (buff 1024)))
  (let (
    (caller tx-sender)
    (sender-info (get-identity-info caller))
    (recipient-info (get-identity-info to-identity))
    (msg-id (var-get message-sequence))
    (current-time (get-block-time))
    (recipient-inbox (get-identity-inbox to-identity))
  )
    ;; Validate both identities exist
    (asserts! (get active sender-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    (asserts! (get active recipient-info) 
              (err RESULT-IDENTITY-NOT-FOUND))
    
    ;; Store the message
    (map-set message-ledger msg-id
      {
        sender: caller,
        recipient: to-identity,
        encrypted-data: encrypted-content,
        timestamp-created: current-time,
        received: false,
        timestamp-received: none
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
    (inbox-items (get-identity-inbox caller))
  )
    ;; Verify caller is recipient
    (asserts! (is-eq (get recipient message-data) caller) 
              (err RESULT-PERMISSION-REJECTED))
    
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

;; Helper function for filtering items
(define-private (not-matching-id (id uint))
  (not (is-eq id msg-id))
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