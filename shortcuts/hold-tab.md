# Hold Tab: app tabs

Deferred to protect the working core. macOS key repeat cannot reliably distinguish holding Tab from pressing it repeatedly, and application tabs require per-app adapters.

- While an app is selected, holding Tab opens a vertical second level for that app's tabs.
- Repeated Tab moves through those tabs; releasing the trigger focuses the selected tab.
- Karabiner may emit a distinct hold gesture so ordinary Tab cycling stays immediate.
- The implementation needs an app adapter boundary: browser tabs are exposed differently from native document tabs, and unsupported apps should keep the normal app-level selection.

First prototype target: one browser, with a visible fallback when tab discovery is unavailable. Do not add it to the core event path until the base switcher is stable.

Safer trigger: map Caps Lock to Hyper in Karabiner. While holding Command after opening Switcher, press Caps Lock/Hyper to enter an explicit vertical window list for the selected app; Tab can then cycle that list. The distinct chord avoids guessing from repeated Tab events.

Keep the macOS shortcuts: ⌘M minimizes one window; ⌘H hides an application. Switcher exposes those as M and H while Command remains held, without adding another mnemonic.
