// Reload the extension if a change is detected.
let initialDevbuildId = null
window.setInterval(async () => {
    const devbuildID = await fetch('/devbuild-id.txt', {
        cache: 'no-cache'
    }).then(response => response.text()).catch(e => null)

    if (devbuildID) {
        if (!initialDevbuildId) {
            initialDevbuildId = devbuildID
        }
        if (devbuildID !== initialDevbuildId) {
            initialDevbuildId = null
            browser.runtime.reload()
        }
    }
}, 500)
