# Hold Tab: app tabs

Deferred until the core ⌘Tab switcher passes testing.

- While an app is selected, holding Tab opens a vertical second level for that app's tabs.
- Repeated Tab moves through those tabs; releasing the trigger focuses the selected tab.
- Karabiner may emit a distinct hold gesture so ordinary Tab cycling stays immediate.
- The implementation needs an app adapter boundary: browser tabs are exposed differently from native document tabs, and unsupported apps should keep the normal app-level selection.

First prototype target: one browser, with a visible fallback when tab discovery is unavailable. Do not add it to the core event path until the base switcher is stable.
