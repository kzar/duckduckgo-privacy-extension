/** @module */

const browserWrapper = require('./wrapper.es6')
const settings = require('./settings.es6')
const tdsStorage = require('./storage/tds.es6')

const {
    generateTrackerBlockingRuleset
} = require('@duckduckgo/ddg2dnr/lib/trackerBlocking')

const manifestVersion = browserWrapper.getManifestVersion()
const SETTING_PREFIX = 'declarative_net_request-'

// Allocate blocks of rule IDs for the different configurations. That way, the
// rules associated with a configuration can be safely cleared without the risk
// of removing rules associated with different configurations.
const ruleIdRangeByConfigName = {
    tds: [1, 10001],
    config: [10001, 20001]
}

// A dummy etag rule is saved with the declarativeNetRequest rules generated for
// each configuration. That way, a consistent extension state (between tds
// configurations, extension settings and declarativeNetRequest rules) can be
// ensured.
function generateEtagRule (id, etag) {
    return {
        id,
        priority: 1,
        condition: {
            urlFilter: etag,
            requestDomains: ['etag.invalid']
        },
        action: { type: 'allow' }
    }
}

/**
 * tdsStorage.onUpdate listener which is called when the configurations are
 * updated and when the background ServiceWorker is restarted.
 * @param {'config'|'tds'} configName
 * @param {string} etag
 */
async function onUpdate (configName, etag) {
    await settings.ready()

    const [ruleIdStart, ruleIdEnd] = ruleIdRangeByConfigName[configName]
    const etagRuleId = ruleIdStart

    const settingName = SETTING_PREFIX + configName
    const previousSettingEtag = settings.getSetting(settingName)?.etag

    // If both the settings entry and declarativeNetRequest rules are present
    // and the etags all match, everything is already up to date.
    if (previousSettingEtag && previousSettingEtag === etag) {
        const existingRules =
              await chrome.declarativeNetRequest.getDynamicRules()
        let previousRuleEtag = null
        for (const rule of existingRules) {
            if (rule.id === etagRuleId) {
                previousRuleEtag = rule.condition.urlFilter
                break
            }
        }

        // No change, rules are already current.
        if (previousRuleEtag && previousRuleEtag === etag) {
            return
        }
    }

    // Otherwise, it is necessary to update the declarativeNetRequest rules and
    // settings again.
    await tdsStorage.ready()

    // Tracker blocking.
    if (configName === 'tds') {
        // Generate the ruleset and ruleId -> tracker domains lookup.
        const {
            ruleset: addRules, trackerDomainByRuleId: lookup
        } = await generateTrackerBlockingRuleset(
            tdsStorage.tds,
            chrome.declarativeNetRequest.isRegexSupported,
            ruleIdStart + 1
        )
        addRules.push(generateEtagRule(etagRuleId, etag))

        // Ensure any existing rules for the configuration are cleared.
        const removeRuleIds = []
        for (let i = ruleIdStart; i <= ruleIdEnd; i++) {
            removeRuleIds.push(i)
        }

        // Install the updated rules and then update the setting entry.
        await chrome.declarativeNetRequest.updateDynamicRules({
            removeRuleIds, addRules
        })
        settings.updateSetting(settingName, { etag, lookup })
    }
}

if (manifestVersion === 3) {
    tdsStorage.onUpdate('config', onUpdate)
    tdsStorage.onUpdate('tds', onUpdate)
}

module.exports = {
    SETTING_PREFIX
}
