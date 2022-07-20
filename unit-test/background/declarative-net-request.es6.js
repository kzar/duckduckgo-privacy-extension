require('../helpers/mock-browser-api')
const tdsStorageStub = require('../helpers/tds.es6')
const tdsStorage = require('../../shared/js/background/storage/tds.es6')

const settings = require('../../shared/js/background/settings.es6')
const browserWrapper = require('../../shared/js/background/wrapper.es6')

const TEST_ETAGS = ['flib', 'flob', 'cabbage']
const TRACKER_BLOCKING_ETAG_RULE_ID = 1

let SETTING_PREFIX

async function updateConfiguration (configName, etag) {
    const listeners = tdsStorageStub.onUpdateListeners.get(configName)
    if (listeners) {
        await Promise.all(
            listeners.map(listener => listener(configName, etag))
        )
    }
}

function validTrackerBlockingLookup (lookup) {
    // Lookup shouldn't be empty.
    if (!lookup || lookup.length === 0) {
        return false
    }

    // Lookup shouldn't include entry for rule ID of 0 (invalid) or of 1 (ETAG
    // rule).
    if (lookup[0] || lookup[1]) {
        return false
    }

    // Lookup should have at least some of the tracking domains.
    const trackingDomains = new Set(Object.keys(tdsStorage.tds.trackers))
    const allTrackingDomainsCount = trackingDomains.size
    for (let i = 2; i < lookup.length; i++) {
        for (const domain of lookup[i].split(',')) {
            trackingDomains.delete(domain)
        }
    }
    if (trackingDomains.size >= allTrackingDomainsCount) {
        return false
    }

    return true
}

function validLookup (configName, lookup) {
    if (configName === 'tds') {
        return validTrackerBlockingLookup(lookup)
    }

    return false
}

describe('declarative-net-request', () => {
    let updateSettingObserver
    let updateDynamicRulesObserver

    let settingsStorage
    let dynamicRulesByRuleId

    const expectState = (
        configName,
        expectedEtag,
        expectedUpdateDynamicRulesCallCount, expectedUpdateSettingCallCount
    ) => {
        const setting = settingsStorage.get(SETTING_PREFIX + configName) || {}
        const {
            etag: actualLookupEtag, lookup: actualLookup
        } = setting
        const etagRule = dynamicRulesByRuleId.get(TRACKER_BLOCKING_ETAG_RULE_ID)
        const actualRuleEtag = etagRule?.condition?.urlFilter

        expect(updateDynamicRulesObserver.calls.count())
            .toEqual(expectedUpdateDynamicRulesCallCount)
        expect(updateSettingObserver.calls.count())
            .toEqual(expectedUpdateSettingCallCount)
        expect(actualLookupEtag).toEqual(expectedEtag)
        expect(validLookup(configName, actualLookup)).toEqual(!!expectedEtag)
        expect(actualRuleEtag).toEqual(expectedEtag)
    }

    beforeAll(() => {
        settingsStorage = new Map()
        dynamicRulesByRuleId = new Map()

        tdsStorageStub.stub()

        spyOn(settings, 'getSetting').and.callFake(
            name => settingsStorage.get(name)
        )
        updateSettingObserver =
            spyOn(settings, 'updateSetting').and.callFake(
                (name, value) => {
                    settingsStorage.set(name, value)
                }
            )
        updateDynamicRulesObserver =
            spyOn(
                chrome.declarativeNetRequest,
                'updateDynamicRules'
            ).and.callFake(
                ({ removeRuleIds, addRules }) => {
                    if (removeRuleIds) {
                        for (const id of removeRuleIds) {
                            dynamicRulesByRuleId.delete(id)
                        }
                    }
                    if (addRules) {
                        for (const rule of addRules) {
                            if (dynamicRulesByRuleId.has(rule.id)) {
                                throw new Error('Duplicate rule ID: ' + rule.id)
                            }
                            dynamicRulesByRuleId.set(rule.id, rule)
                        }
                    }
                    return Promise.resolve()
                }
            )
        spyOn(chrome.declarativeNetRequest, 'getDynamicRules').and.callFake(
            () => Array.from(dynamicRulesByRuleId.values())
        )

        // Force manifest version to '3' before requiring the
        // declarativeNetRequest code to prevent the MV3 code paths from being
        // skipped.
        spyOn(browserWrapper, 'getManifestVersion').and.callFake(() => 3)
        SETTING_PREFIX =
            require('../../shared/js/background/declarative-net-request.es6')
                .SETTING_PREFIX
    })

    beforeEach(() => {
        updateSettingObserver.calls.reset()
        updateDynamicRulesObserver.calls.reset()
        settingsStorage.clear()
        dynamicRulesByRuleId.clear()
    })

    it('Updates the tracker blocking DNR rules as required', async () => {
        expectState('tds', undefined, 0, 0)

        // Nothing saved, rules should be added.
        await updateConfiguration('tds', TEST_ETAGS[0])
        expectState('tds', TEST_ETAGS[0], 1, 1)

        // Rules for that ruleset are already present, skip.
        await updateConfiguration('tds', TEST_ETAGS[0])
        expectState('tds', TEST_ETAGS[0], 1, 1)

        // Rules are outdated, replace with new ones.
        await updateConfiguration('tds', TEST_ETAGS[1])
        expectState('tds', TEST_ETAGS[1], 2, 2)

        // Settings missing, add rules again.
        settingsStorage.clear()
        await updateConfiguration('tds', TEST_ETAGS[1])
        expectState('tds', TEST_ETAGS[1], 3, 3)

        // Rules missing, add again.
        dynamicRulesByRuleId.clear()
        await updateConfiguration('tds', TEST_ETAGS[1])
        expectState('tds', TEST_ETAGS[1], 4, 4)

        // All good again, skip.
        await updateConfiguration('tds', TEST_ETAGS[1])
        expectState('tds', TEST_ETAGS[1], 4, 4)
    })
})
