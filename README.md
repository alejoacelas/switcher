<!--ai-->
# Cmd-Tab

My small macOS app that reproduces the AltTab setup I use on ⌘Tab, without AltTab's unused configuration surface.

```sh
./scripts/build-app.sh
open .build/CmdTab.app
```

Grant Accessibility and Screen Recording when macOS asks, then quit AltTab so both apps do not intercept ⌘Tab. The exact behavior copied from AltTab is in [configuration.md](configuration.md).

The build uses my stable local signing identity. Stable signing keeps macOS privacy grants valid across rebuilds; never replace it with ad-hoc signing.
<!--/ai-->
