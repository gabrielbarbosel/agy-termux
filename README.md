# agy-termux

Run [Antigravity CLI](https://antigravity.google) on Android/Termux — no root required.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/gabrielbarbosel/agy-termux/main/install.sh | bash
source ~/.bashrc
```

That's it. Dependencies, binary download, patching — all handled automatically.

## Usage

```bash
agy                 # Start (same as desktop)
agy update          # Update to latest version
agy --version       # Show version
```

## How it works

The official AGY binary targets glibc + 48-bit VA space. Android uses Bionic + 39-bit VA. This adapter bridges the gap:

| File | Role |
|---|---|
| `wrapper.sh` | Routes execution through glibc's dynamic linker |
| `update.sh` | Downloads, patches, verifies, rolls back on failure |
| `self-heal.sh` | Auto-repairs if a native update overwrites the wrapper |
| `patch` | Prebuilt Go tool: rewrites ARM64 instructions (TCMalloc VA48→VA39, `faccessat2`→`faccessat`). Source in `patcher/` |
| `dns-heal.js` | Heals the glibc resolv.conf/hosts so lookups work on Android |

## Requirements

- Termux from [GitHub releases](https://github.com/termux/termux-app/releases) (not Play Store)
- ARM64 device

All package dependencies (`glibc`, `curl`) are installed automatically.

## Uninstall

```bash
rm -rf ~/.local/share/agy-termux ~/.local/bin/agy
# Remove the agy() function from ~/.bashrc
```

## Credits

Patching approach based on work by [@hjotha](https://github.com/hjotha), [@Brajesh2022](https://github.com/Brajesh2022), and [wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux).

## License

MIT
