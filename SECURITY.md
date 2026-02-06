# Security Considerations for SealRegistry

This document outlines security considerations and audit recommendations for the describe-net SealRegistry smart contract.

## Overview

The SealRegistry contract manages categorical reputation "seals" between humans and AI agents. It is designed to be permissionless for human evaluations while enforcing domain restrictions for agent evaluations.

## Architecture

```
┌─────────────────────┐      ┌──────────────────────┐
│   SealRegistry      │◄─────│   IIdentityRegistry  │
│                     │      │   (External)         │
│  - Issue seals      │      └──────────────────────┘
│  - Revoke seals     │
│  - Track domains    │
└─────────────────────┘
```

## Access Control Model

| Function | Access Level | Notes |
|----------|--------------|-------|
| `issueSealA2H` | Registered agents only | Must have seal type in registered domains |
| `issueSealH2A` | Any address | Agent must exist in IdentityRegistry |
| `issueSealH2H` | Any address | No restrictions on subject |
| `revokeSeal` | Original evaluator only | Cannot revoke others' seals |
| `registerAgentSealDomains` | Registered agents only | Adds to existing domains |
| `addSealType` | Owner only | Creates new valid seal types |

## Known Risks & Considerations

### 1. Identity Registry Trust

**Risk Level:** High

The contract trusts the external `IIdentityRegistry` for agent verification. If the identity registry is compromised or returns incorrect data, it could allow:
- Unregistered addresses to issue A→H seals
- Seals to be issued to non-existent agents

**Recommendation:**
- Ensure the IdentityRegistry contract is audited and secure
- Consider adding a registry update mechanism with timelock
- Monitor for registry anomalies

### 2. Self-Sealing

**Risk Level:** Low-Medium

The contract allows addresses to seal themselves (e.g., `human1.issueSealH2H(human1, ...)`). While this may be intended behavior, it could:
- Enable reputation manipulation
- Create misleading trust signals

**Recommendation:**
- Document whether self-sealing is intended
- Consider adding a `require(subject != msg.sender)` check if undesired
- Downstream consumers should filter or weight self-seals differently

### 3. Zero Address Seals

**Risk Level:** Low

The contract allows sealing `address(0)` in H→H seals. This doesn't cause contract issues but may:
- Create orphaned seal records
- Waste gas on meaningless operations

**Recommendation:**
- Consider adding `require(subject != address(0))` validation
- Or document this as acceptable edge case

### 4. Seal Spam / Griefing

**Risk Level:** Medium

Any address can issue unlimited H→H and H→A seals, which could:
- Bloat storage with spam seals
- Create noise in reputation data
- Increase gas costs for `getSubjectSeals` and `getSubjectSealsByType`

**Recommendation:**
- Consider rate limiting (per address, per time period)
- Consider requiring a small fee or stake
- Off-chain indexers should implement spam filtering

### 5. Unbounded Array Growth

**Risk Level:** Medium

The `_subjectSeals` and `_evaluatorSeals` arrays grow unboundedly. For addresses with many seals:
- `getSubjectSeals()` may hit gas limits
- `getSubjectSealsByType()` iterates twice over all seals

**Recommendation:**
- Consider pagination for view functions
- Add `limit` and `offset` parameters
- Document gas considerations for heavy users

### 6. Domain Registration is Append-Only

**Risk Level:** Low

Once an agent registers seal domains, they cannot remove them:
```solidity
agentSealDomains[msg.sender][sealTypes[i]] = true;
```

**Recommendation:**
- Add `unregisterAgentSealDomains()` function if needed
- Or document this as intended behavior

### 7. No Seal Update Mechanism

**Risk Level:** Low

Seals cannot be updated once issued. To change a score, the evaluator must:
1. Revoke the old seal
2. Issue a new seal

This creates two records instead of one updated record.

**Recommendation:**
- Consider adding `updateSeal()` function if updates are common
- Or document this as intended behavior (immutable history)

### 8. Expiration Time Validation

**Risk Level:** Low

No validation that `expiresAt` is in the future:
```solidity
sealId = _issueSeal(..., expiresAt);  // Could be in the past
```

**Recommendation:**
- Consider `require(expiresAt == 0 || expiresAt > block.timestamp)`
- Or accept that immediate expiration is valid edge case

### 9. Evidence Hash is Unvalidated

**Risk Level:** Low

The `evidenceHash` parameter is not validated:
- Could be `bytes32(0)` (empty)
- Could reference non-existent off-chain data
- No on-chain verification of evidence existence

**Recommendation:**
- This is acceptable for many use cases
- Document that evidence verification is off-chain responsibility

## Gas Considerations

| Operation | Gas Notes |
|-----------|-----------|
| `issueSealA2H` | ~100k gas (includes external call + storage) |
| `issueSealH2H` | ~80k gas (no external calls) |
| `getSubjectSealsByType` | O(n) where n = total seals for subject |
| `registerAgentSealDomains` | O(m) where m = number of seal types |

## Upgrade Path

The contract inherits from OpenZeppelin's `Ownable` but is **not upgradeable**. Future changes require:
1. Deploying a new contract
2. Migrating state (manual or via migration script)
3. Updating all integrations

**Recommendation:**
- Consider using UUPS or Transparent Proxy pattern for upgradeability
- Or establish clear versioning strategy

## Recommended Audit Focus Areas

1. **IdentityRegistry integration** - Verify external call safety
2. **Access control** - Ensure only authorized callers can issue/revoke
3. **State consistency** - Verify seal arrays are properly maintained
4. **Event emission** - Ensure all state changes emit events
5. **Reentrancy** - Review external calls (currently only to IdentityRegistry)
6. **Integer overflow** - Verify uint48 timestamp handling

## Testing Recommendations

- [x] Happy path for all seal types (A2H, H2A, H2H)
- [x] Authorization failures
- [x] Invalid seal type rejection
- [x] Score boundary validation (0, 100, 101)
- [x] Expiration boundary testing
- [x] Revocation edge cases
- [x] Self-sealing behavior
- [ ] Fuzz testing for all inputs
- [ ] Invariant testing (e.g., totalSeals == sum of all arrays)
- [ ] Gas benchmarking under load

## Incident Response

If a vulnerability is discovered:
1. Pause agent domain registrations (if mechanism exists)
2. Deploy patched contract
3. Migrate valid seals
4. Update IdentityRegistry reference if needed

## Contact

For security disclosures, please contact: [security contact TBD]

---

*Last updated: 2026-02-06*
*Contract version: 1.0.0*
