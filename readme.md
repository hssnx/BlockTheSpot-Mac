# BlockTheSpot‑Mac (Active Fork)

**A maintained fork of Nuzair46’s BlockTheSpot‑Mac adding support for Spotify** **1.2.62+ (V8‑snapshot builds) and Apple Silicon.**

|                               |                                         |
| ----------------------------- | --------------------------------------- |
| **Maintainer**                | Hassan – feel free to open issues / PRs |
| **Last updated**              | 21 May 2025                             |
| **Last tested Spotify build** | **1.2.63.394**                          |

> _The original project was archived on 17 Dec 2024. This fork keeps the lights on._

---

## 🚀 Features

- Blocks banner / video / audio ads
- Removes telemetry (Sentry, logging/v3)
- Unlocks unlimited track skips
- _Optional_ flags

  - hide podcasts / audiobooks from Home
  - block automatic updates
  - enable Developer Mode

- Works on Intel **and** Apple Silicon (M‑series) Macs, Spotify ≥ 1.1.70 and ≤ 1.2.64 (snapshot layout supported)

---

## 🔧 Installation / Update

> **Prerequisites**
> • macOS 10.11+
> • `perl`, `zip`, `unzip`, **GNU sed** (`brew install gnu-sed`)
> • Xcode CLI tools (`xcode-select --install`) unless you skip codesign on Intel (`-S` flag)

```bash
# Close Spotify first
bash <(curl -sSL https://raw.githubusercontent.com/HassanDev/BlockTheSpot-Mac/main/install.sh) [-flags]
```

### Common flags

| Flag | Purpose                                      |
| ---- | -------------------------------------------- |
| `-f` | Force re‑patch even if a backup exists       |
| `-h` | Hide podcasts, episodes & audiobooks on Home |
| `-u` | Block automatic updates                      |
| `-d` | Enable Developer Mode                        |
| `-S` | Skip codesign (Intel only)                   |
| `-U` | **Uninstall** and restore original files     |

Example – hide non‑music shelves and stop future updates:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/HassanDev/BlockTheSpot-Mac/main/install.sh) -f -hu
```

---

## 🗑 Uninstall

```bash
bash <(curl -sSL https://raw.githubusercontent.com/HassanDev/BlockTheSpot-Mac/main/install.sh) -U
```

or just reinstall Spotify from the official dmg.
