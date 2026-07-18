# Plan: Migrate Auth Method Display to Backend `auth_types` Array

## Overview

Replace the fragile local `hasSeedphraseLocally` heuristic with the new
`auth_types` array returned by `GET /network/user`.  This eliminates the
server-error-substring parsing, the local state hack, and incorrect
method listing on accounts with wallet + seedphrase.

## SDK Changes (`beta/custom-server` on `Ryanmello07/urnetwork-sdk`)

### 1. `network_user_view_controller.go` — Extend `NetworkUser` struct

```go
type NetworkUser struct {
    UserId         *Id              `json:"userId"`
    UserName       string           `json:"user_name"`
    UserAuth       string           `json:"user_auth,omitempty"`
    Verified       bool             `json:"verified"`
    AuthType       string           `json:"auth_type"`
    NetworkName    string           `json:"network_name"`
    WalletAddress  string           `json:"wallet_address,omitempty"`

    // NEW: multi-auth fields
    AuthTypes       []string        `json:"auth_types,omitempty"`
    WalletAuths     []WalletAuth    `json:"wallet_auths,omitempty"`
    SeedphraseAuths []SeedphraseAuth `json:"seedphrase_auths,omitempty"`
}

type WalletAuth struct {
    WalletAddress string `json:"wallet_address"`
    Blockchain    string `json:"blockchain"`
}

type SeedphraseAuth struct {
    CreateTime string `json:"create_time"`
}
```

**gomobile note:** Go slices (`[]string`,`[]WalletAuth`,`[]SeedphraseAuth`)
export to Swift as, respectively, `func (self SdkNetworkUser) AuthTypes()
*SdkStringList`, `func (self SdkNetworkUser) WalletAuths()
*SdkWalletAuthList`, etc.  These already exist in the generated bindings.

`WalletAuth` / `SeedphraseAuth` must be exported types.  If gomobile
refuses to export them, fall back to a single `AuthTypes []string` only
and keep the existing `authType` for single-auth read.

### 2. `api.go` — No change needed

`GetNetworkUserResult` already deserialises the full JSON response.
New `auth_types` etc. will be deserialised into `NetworkUser` as long as
JSON tags match.

## iOS Changes (`feat/seedphrase-auth-ios` on `Ryanmello07/urnetwork-ios`)

### 1. `SettingsForm-iOS.swift` — Replace `parseAuthMethods`

**Current:** reads `networkUser.authType` (single string), appends
seedphrase via `hasSeedphraseLocally` local state hack.

**New:**

```swift
private func parseAuthMethods(_ networkUser: SdkNetworkUser) -> [String] {
    var methods: [String] = []
    
    // Use the new auth_types array from the backend
    let authTypes = networkUser.authTypes
    if authTypes.len() > 0 {
        for i in 0..<authTypes.len() {
            if let method = authTypes.get(i) {
                methods.append(method)
            }
        }
    } else {
        // Fallback for old server: read single authType + userAuth
        let authType = networkUser.authType
        if !authType.isEmpty { methods.append(authType) }
        let userAuth = networkUser.userAuth
        if !userAuth.isEmpty {
            let methodLabel = userAuth.contains("@") ? "email" : userAuth
            if !methods.contains(methodLabel) {
                methods.append(methodLabel)
            }
        }
    }
    
    return methods
}
```

**Also remove** `hasSeedphraseLocally` from the seedphrase section UI
and from `SettingsViewModel` (see below).

### 2. `SettingsForm-macOS.swift` — Same as iOS

Mirror the `parseAuthMethods` change and remove local seedphrase hacks.

### 3. `SettingsViewModel.swift` — Remove `hasSeedphraseLocally`

- Delete `@Published var hasSeedphraseLocally: Bool`
- Delete references to `hasSeedphraseLocally` in `executeGenerateSeedphrase`
  and `executeRegenerateSeedphrase`
- The seedphrase regenerate auto-detection ("already exists" error)
  can be simplified: just show the generate button normally; the
  auth list refreshes from the server on next fetch

### 4. `SettingsView.swift` — Optional cleanup

The `.onOpenURL` handler with `handleWalletDeepLink` stays as-is.
No changes needed.

### 5. `SettingsForm-iOS.swift` — Seedphrase UI section

**Current:** uses `hasSeedphraseLocally || networkUser?.authType == "seedphrase"`

**New:** read from `authTypes`:

```swift
// Replace the seedphrase section condition:
if let networkUser = networkUserViewModel?.networkUser {
    let authTypes = networkUser.authTypes
    let hasSeedphrase: Bool = {
        for i in 0..<authTypes.len() {
            if authTypes.get(i) == "seedphrase" { return true }
        }
        return false
    }()
    
    if hasSeedphrase {
        // show seedphrase info + regenerate button
    } else {
        // show generate button
    }
}
```

## Data Flow

```
Backend returns GET /network/user
    ↓
SDK deserialises into SdkNetworkUser with new fields
    ↓
NetworkUserViewModel publishes updated networkUser
    ↓
SettingsForm reads authTypes array from networkUser
    ↓
parseAuthMethods builds method list from authTypes
    ↓
UI shows Sign-In Methods list + seedphrase section
```

## Edge Cases

| Scenario | `auth_types` | Behaviour |
|---|---|---|
| Wallet only | `["solana"]` | Shows "Solana Wallet"; seedphrase generate offered |
| Wallet + seedphrase | `["solana", "seedphrase"]` | Both shown; seedphrase shows "Regenerate" |
| Seedphrase only | `["seedphrase"]` | Shows only "Seedphrase" |
| Email + seedphrase + wallet | `["email", "solana", "seedphrase"]` | All three shown |
| Google SSO + seedphrase | `["google", "seedphrase"]` | Both shown |
| Old server (no auth_types) | empty | Falls back to `authType` + `userAuth` |

## Testing Strategy

1. **Build CI** — Push SDK changes + iOS changes, verify compile
2. **Manual verification** — Test with server that returns new fields
3. **Verify remove auth** — Removing a method should refresh `auth_types` on next `/network/user` fetch

## Open Questions

1. `WalletAuth` / `SeedphraseAuth` structs — are these gomobile-exportable?
   If not, fall back to `AuthTypes []string` only.
2. Refresh trigger — does the `NetworkUserViewModel` auto-refresh after
   add/remove auth? Currently the SDK's `NetworkUserViewController`
   fetches on start. We may need to call `refreshNetworkUser()` after
   add/remove.
