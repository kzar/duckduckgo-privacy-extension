module.exports = (uaString) => {
    // Firefox < 65 does not support `globalThis`. We don't support Node.js
    // versions without `globalThis` support, so we can just check `self` and
    // `window`.
    if (typeof globalThis === 'undefined')
    {
        if (typeof self !== 'undefined')
            self.globalThis = self
        else if (typeof window !== 'undefined')
            window.globalThis = window
    }

    if (!uaString) uaString = globalThis.navigator.userAgent

    let browser
    let version

    try {
        let parsedUaParts = uaString.match(/(Firefox|Chrome|Edg)\/([0-9]+)/)
        if (uaString.match(/(Edge?)\/([0-9]+)/)) {
            // Above regex matches on Chrome first, so check if this is really Edge
            parsedUaParts = uaString.match(/(Edge?)\/([0-9]+)/)
        }
        browser = parsedUaParts[1]
        version = parsedUaParts[2]

        // Brave doesn't include any information in the UserAgent
        if (window.navigator.brave) {
            browser = 'Brave'
        }
    } catch (e) {
        // unlikely, prevent extension from exploding if we don't recognize the UA
        browser = version = ''
    }

    let os = 'o'
    if (globalThis.navigator.userAgent.indexOf('Windows') !== -1) os = 'w'
    if (globalThis.navigator.userAgent.indexOf('Mac') !== -1) os = 'm'
    if (globalThis.navigator.userAgent.indexOf('Linux') !== -1) os = 'l'

    return {
        os,
        browser,
        version
    }
}
