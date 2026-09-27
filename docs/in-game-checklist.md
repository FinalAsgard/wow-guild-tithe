# Initial in-game checklist

Use this checklist with the current World of Warcraft: Forever client.

## Install

1. Copy the repository folder to `_classic_beta_/Interface/AddOns/GuildTithe`.
2. Confirm `GuildTithe_Camelot.toc` and the `Core` and `Adapters` folders are directly inside `GuildTithe`.
3. Start or restart the client so it rescans add-ons.
4. At character selection, open **AddOns** and confirm **Guild Tithe** appears enabled and is not marked out of date. The manifest targets Forever interfaces `16000` and `16001`.
5. Enable visible Lua errors with `/console scriptErrors 1` for the test session.

## Verify

1. Log in to a character and confirm no Guild Tithe Lua error appears during loading.
2. Enter `/gt` and confirm chat prints `Guild Tithe: /gt help - show available commands` once.
3. Enter `/gt help` and confirm the same help appears once.
4. Enter `/gt unknown` and confirm the add-on reports an unknown command and suggests `/gt help` without raising an error.
5. Run `/reload`, then repeat `/gt` to confirm lifecycle and slash-command registration work after a UI reload.

Record the Forever build from `/dump GetBuildInfo()` and any Lua error text when reporting a failure.
