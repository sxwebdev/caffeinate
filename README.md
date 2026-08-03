# Caffeinate

A macOS menubar app to temporarily prevent the Mac from sleeping.

## How does it work

Left-clicking the cup will toggle Caffeinate. If the cup is filled, your Mac won't go to sleep anymore.
Right clicking the cup will open the settings. From there, you can also quit the app.

While active, the app holds an IOKit power assertion. Settings offer two modes:

| Mode                  | Assertion                     | Equivalent      | Behaviour                                                                                       |
| --------------------- | ----------------------------- | --------------- | ----------------------------------------------------------------------------------------------- |
| Keep the display on   | `PreventUserIdleDisplaySleep` | `caffeinate -d` | The display stays lit, which also keeps the system awake.                                       |
| Let the display sleep | `PreventUserIdleSystemSleep`  | `caffeinate -i` | The display switches off on its own, the system keeps running. Useful for long background jobs. |

Both modes only block _idle_ sleep. Closing the lid, choosing Sleep from the Apple
menu, or running out of battery still puts the Mac to sleep. Verify the live state
with `pmset -g assertions | grep Caffeinate`.

![cup1](./Images/cup1.png) dark mode Caffeinate active
![cup2](./Images/cup2.png) dark mode Caffeinate inactive

![cup3](./Images/cup3.png) light mode Caffeinate active
![cup4](./Images/cup4.png) light mode Caffeinate inactive

## Requirements

The app requires macOS 11 or later to run. If you are using macOS 13, you can add the app to the login items via the app settings.

## Installation

You can compile the app yourself using xcode `xcodebuild -configuration Release` or you can download a compiled version from [releases](https://github.com/sxwebdev/caffeinate/releases).

## FAQ

**How do I quit?**

Right-click the menu bar item, then go to Settings and press Quit.

## TODO

Even if the lid is closed, prevent the Mac from sleeping. This probably requires root privileges.
