# Hold Tab: app tabs

Deferred to protect the working core. macOS key repeat cannot reliably distinguish holding Tab from pressing it repeatedly, and application tabs require per-app adapters.

- While an app is selected, holding Tab opens a vertical second level for that app's tabs.
- Repeated Tab moves through those tabs; releasing the trigger focuses the selected tab.
- Karabiner may emit a distinct hold gesture so ordinary Tab cycling stays immediate.
- The implementation needs an app adapter boundary: browser tabs are exposed differently from native document tabs, and unsupported apps should keep the normal app-level selection.

First prototype target: one browser, with a visible fallback when tab discovery is unavailable. Do not add it to the core event path until the base switcher is stable.

Safer trigger: use Karabiner to emit an otherwise unused key chord when Tab crosses a hold threshold. Switcher can treat that chord as an explicit request for a vertical window list without guessing from repeated Tab events.

For now, press X with the switcher open to minimize the selected window. X stays under the left hand near ⌘Tab; minimized windows immediately leave the list.
