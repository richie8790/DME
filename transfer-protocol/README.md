
# 📡 Decentralized Message Exchange - Edition 1

A fully on-chain decentralized messaging framework built in Clarity. It supports secure, encrypted message exchange between registered identities, complete with channel authorization, message timeouts, and system-wide tracking. This contract is ideal for decentralized identity and communication solutions requiring censorship resistance, privacy, and accountability.

---

## 🔧 Features

* ✅ **Identity Registration** with optional encryption keys
* ✅ **Secure Message Sending** with expiration and types
* ✅ **Message Tracking** (sent/received, timestamps, inbox)
* ✅ **Channel Authorization** to control who can send messages
* ✅ **Inbox Cleanup** and message deletion support
* ✅ **Admin-Controlled Framework Configuration**
* ✅ **Efficient Query Utilities** for stats, identities, and messages
* ✅ **Batch Processing** for scalable off-chain integrations

---

## 🧱 Data Structures

### Identity Profile (`identity-directory`)

* `active: bool`
* `encryption-key: (optional (buff 33))`
* `enrollment-time: uint`
* `sent-count: uint`
* `received-count: uint`
* `recent-activity: uint`

### Message Object (`message-ledger`)

* `sender: principal`
* `recipient: principal`
* `encrypted-data: (buff 1024)`
* `timestamp-created: uint`
* `received: bool`
* `timestamp-received: (optional uint)`
* `expiration-block: uint`
* `message-type: (string-utf8 20)`

### Channels & Inbox

* `identity-inbox`: `principal -> (list 50 uint)`
* `identity-channels`: `principal -> (list 100 principal)`

---

## 🚀 How It Works

### 1. Identity Creation

Users register themselves with an optional encryption key using:

```clojure
(create-identity (buff 33))
```

### 2. Channel Management

Users must authorize senders by opening communication channels:

```clojure
(open-channel principal)
(close-channel principal)
```

### 3. Sending Messages

Authorized users can send encrypted messages with an optional timeout:

```clojure
(send-message recipient content message-type timeout-period)
```

### 4. Receiving Messages

Recipients mark messages as received, which updates their inbox:

```clojure
(mark-received msg-id)
```

### 5. Inbox Maintenance

Old or expired messages can be cleaned:

```clojure
(clean-inbox)
```

---

## 🛡 Result Codes

| Code   | Meaning                     |
| ------ | --------------------------- |
| `u300` | Identity not found          |
| `u301` | Identity already registered |
| `u302` | Permission rejected         |
| `u303` | Message not found           |
| `u304` | Message size exceeded       |
| `u305` | Key verification failed     |
| `u306` | Operation failed            |
| `u307` | Channel not found           |
| `u308` | Channel already exists      |
| `u309` | Self-channel forbidden      |
| `u310` | Message expired             |
| `u311` | Channel limit reached       |

---

## 🧪 Query Functions

* `get-identity-info`
* `get-identity-inbox`
* `get-message-by-id`
* `get-message-count`
* `get-identity-channels`
* `is-channel-active`
* `is-message-valid`
* `get-framework-stats`

---

## ⚙️ Admin Functions

Only the admin (contract deployer) can:

* Initialize the framework: `(setup-framework)`
* Transfer admin rights: `(change-admin new-admin)`
* Configure system parameters: `(update-framework-config timeout)`

---

## 📦 Deployment & Testing

1. Deploy on a Clarity-compatible network (Stacks testnet/mainnet).
2. Interact via Clarinet, Hiro Wallet, or frontend DApps using:

   * Clarity JS SDK
   * PostConditions for secured operations

---

## 🧠 Future Ideas

* Group messaging / broadcast
* Off-chain indexing & delivery receipts
* Mutable system-wide configuration registry
* Encryption interoperability with decentralized identities
