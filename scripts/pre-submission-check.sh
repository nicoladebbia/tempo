#!/bin/bash
# Per BUILD_PLAN Step 20.5 — Pre-submission validation script.
# Per APP_STORE_COMPLIANCE.md Section 8 — Pre-Submission Checklist.
# Run before submitting to App Store.

PASS=0
FAIL=0
WARN=0

pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }

echo "========================================"
echo "Tempo Pre-Submission Validation"
echo "========================================"
echo ""

# 1. Code & Build Checks
echo "--- Code & Build ---"

# Check no TODO/FIXME in production code
TODO_COUNT=$(grep -r "TODO\|FIXME\|HACK\|XXX" Tempo/Tempo/ --include="*.swift" -c 2>/dev/null | awk -F: '{sum+=$2}END{print sum}' || echo "0")
if [ "$TODO_COUNT" -gt 0 ]; then
    warn "Found $TODO_COUNT TODO/FIXME comments in production code"
else
    pass "No TODO/FIXME in production code"
fi

# Check no print statements in production code (should use Logger)
PRINT_COUNT=$(grep -r "print(" Tempo/Tempo/ --include="*.swift" -c 2>/dev/null | awk -F: '{sum+=$2}END{print sum}' || echo "0")
if [ "$PRINT_COUNT" -gt 0 ]; then
    warn "Found $PRINT_COUNT print() statements — use Logger instead"
else
    pass "No print() statements in production code"
fi

# Check no force unwraps in production code (excluding tests)
FORCE_UNWRAP=$(grep -r "![^=]" Tempo/Tempo/ --include="*.swift" | grep -v "IBOutlet\|IBAction\|@objc\|//\|#if\|fatalError\|precondition" | grep -c "!$\|!\." 2>/dev/null || echo "0")
if [ "$FORCE_UNWRAP" -gt 20 ]; then
    warn "Found $FORCE_UNWRAP potential force unwraps — review for safety"
else
    pass "Force unwrap count acceptable ($FORCE_UNWRAP)"
fi

echo ""

# 2. Privacy & Compliance
echo "--- Privacy & Compliance ---"

# Check cloudKitDatabase is .none for health models
if grep -r "cloudKitDatabase:" Tempo/Tempo/ --include="*.swift" | grep -v "\.none" | grep -q .; then
    fail "Found cloudKitDatabase not set to .none — health data must not sync to iCloud"
else
    pass "All cloudKitDatabase settings are .none"
fi

# Check no IDFA/ATT usage
if grep -r "ATTrackingManager\|ASIdentifierManager\|advertisingIdentifier" Tempo/Tempo/ --include="*.swift" | grep -q .; then
    fail "Found IDFA/ATT usage — Tempo should not use tracking"
else
    pass "No IDFA/ATT usage found"
fi

# Check AI consent gating exists
if grep -r "aiConsent\|aiConsentGranted\|AI Features" Tempo/Tempo/ --include="*.swift" | grep -q .; then
    pass "AI consent gating found in code"
else
    warn "No AI consent gating found — ensure Claude API calls are gated"
fi

echo ""

# 3. HealthKit Compliance
echo "--- HealthKit ---"

# Check HealthKit entitlement exists
if grep -q "com.apple.developer.healthkit" Tempo/Tempo/Tempo.entitlements 2>/dev/null; then
    pass "HealthKit entitlement present"
else
    fail "HealthKit entitlement missing"
fi

# Check NSHealthShareUsageDescription in Info.plist or xcconfig
if grep -r "NSHealthShareUsageDescription\|HealthShare" Tempo/ --include="*.plist" --include="*.xcconfig" | grep -q .; then
    pass "NSHealthShareUsageDescription configured"
else
    warn "NSHealthShareUsageDescription not found — verify in build settings"
fi

echo ""

# 4. StoreKit/Subscriptions
echo "--- Subscriptions ---"

# Check subscription service exists
if [ -f "Tempo/Tempo/Services/Subscriptions/SubscriptionService.swift" ]; then
    pass "SubscriptionService exists"
else
    fail "SubscriptionService not found"
fi

# Check PaywallView exists
if [ -f "Tempo/Tempo/Views/Shared/PaywallView.swift" ]; then
    pass "PaywallView exists"
else
    fail "PaywallView not found"
fi

# Check restore purchases functionality
if grep -r "restorePurchases\|Restore Purchases" Tempo/Tempo/ --include="*.swift" | grep -q .; then
    pass "Restore Purchases functionality found"
else
    fail "Restore Purchases missing — required by App Store"
fi

# Check manage subscription link
if grep -r "apps.apple.com/account/subscriptions\|Manage Subscription" Tempo/Tempo/ --include="*.swift" | grep -q .; then
    pass "Manage Subscription link found"
else
    warn "Manage Subscription link not found in Settings — add before submission"
fi

echo ""

# 5. Legal
echo "--- Legal ---"

if [ -f "legal/privacy-policy.html" ]; then
    pass "Privacy policy exists"
else
    fail "Privacy policy missing"
fi

if [ -f "legal/terms-of-service.html" ]; then
    pass "Terms of service exists"
else
    fail "Terms of service missing"
fi

echo ""

# 6. Analytics
echo "--- Analytics ---"

if [ -f "Tempo/Tempo/Services/Analytics/AnalyticsService.swift" ]; then
    pass "AnalyticsService exists"
else
    fail "AnalyticsService not found"
fi

# Check no health data in analytics events
if grep -r "heartRate\|hrv\|recoveryScore\|sleepHours\|calories\b" Tempo/Tempo/Services/Analytics/ --include="*.swift" 2>/dev/null | grep -v "//\|completion_rate\|focus_score" | grep -q .; then
    warn "Potential health data in analytics events — verify compliance"
else
    pass "No health biometrics in analytics events"
fi

echo ""

# Summary
echo "========================================"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "FIX ALL FAILURES before submitting to App Store."
    exit 1
fi

echo ""
echo "Pre-submission check complete."
echo ""
echo "MANUAL STEPS REMAINING:"
echo "  1. Archive in Xcode: Product > Archive"
echo "  2. Upload to App Store Connect via Xcode Organizer"
echo "  3. Fill in App Store Connect metadata (use appstore/listing.md)"
echo "  4. Add screenshots (6.7\" iPhone 15 Pro Max, 4.7\" iPhone SE)"
echo "  5. Set privacy labels (use appstore/privacy-labels.md)"
echo "  6. Add App Review Notes (see docs/APP_STORE_COMPLIANCE.md Section 4.2)"
echo "  7. Select Manual Release"
echo "  8. Submit for review"
