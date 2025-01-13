# MenuBarVolume

A persistent volume indicator in your menu bar for macOS Monterey (12) and subsequent versions.

## Why?

For some godforsaken reason, a recent version of macOS made it so that when using headphones or a similar output device, the old volume indicator is replaced with a static icon of your headphones. This makes it impossible to tell at a glance if your volume is muted.

This app, when launched, adds an additional icon in the menu bar which has the old, more useful visual indicator.

<img src="screenshot.png"/>

There's also an off-by-default toggle to show the exact percentage as well.

## Setting expectations

This is the first Mac app I've made. It's simple, and works for me, but I can't promise it'll work for you.

And yes, if you don't have headphones connected, this will cause you to have two speaker icons in the menu bar. You can just quit this app in that case, if that annoys you.

## Getting

I can't be bothered to join the Apple Developer Program just to distribute this, but you can download the `.app` from the [Releases page](https://github.com/bakkot/MenuBarVolume/releases).

You will probably need to right-click and "open" this to bypass Gatekeeper.

## Building

This repo contains the XCode project files I used. You probably need XCode 14 (or later), since that's what I used.

### A note on running as an agent

To get the app to launch without an icon in the doc, you need to set

```
<key>LSUIElement</key>
<true/>
```
in the app's `Info.plist`. You are supposedly able to set properties by going to the "Info" page for the target and adding your property, but this only worked on some versions of XCode for me.

Regardless, I worked around this by manually editing the `plist` and then re-signing with `sudo codesign -f -s -  MenuBarVolume.app`.
