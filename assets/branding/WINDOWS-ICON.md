# Shared transparent application icon

`app-icon.png` is the shared transparent master used by the macOS application ICNS, Mac installer logo, Windows EXE ICO, WPF logo and window icon. The visible blue rounded-square body and its artwork are retained; the exterior navy rectangular background is removed. `windows-installer.png` is the opaque original input retained for provenance and must not be used in installers.

The master was cut out with the built-in imagegen tool on 2026-10-18 using the user's selected original. No plugin API was called. The generated alpha channel is preserved. The input remains in `windows-installer.png`.

Prompt: Use case background-extraction. Keep the entire glossy deep-blue rounded-square body, internal white crop brackets, cyan landscape pictures and star. Remove only the navy background outside the actual curved silhouette. Transparent exterior, no opaque mat or added backdrop, smooth antialiased edge, preserve the artwork, colors, proportions and centered composition with approximately 8–9% transparent margin.

Validation must check transparent exterior and rounded corners, opaque center, native Mac bundle/Dock image and all Windows shell sizes (16, 24, 32, 48, 64, 128 and 256 px), rather than only checking that an icon exists. Alpha values near zero at antialiased margins are allowed; an opaque background is rejected. Light, dark and checkerboard previews are provided for visual review.
