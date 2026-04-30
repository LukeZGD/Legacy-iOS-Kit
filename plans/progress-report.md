# LegacyKit UI Rebuild — Progress Report

**Date:** 2026-04-30  
**Status:** Phase 1 Complete, Phase 2 Complete

---

## Completed Changes

### Phase 1: Foundation (100% Complete)

#### Rust Backend
| File | Action | Description |
|------|--------|-------------|
| `src-tauri/Cargo.toml` | Modified | Added `thiserror = "2"` dependency |
| `src-tauri/src/error.rs` | Created | Unified `AppError` enum (DeviceNotFound, CommandFailed, Io, Parse) with thiserror + Serialize |
| `src-tauri/src/models/mod.rs` | Created | Module declaration for `device` |
| `src-tauri/src/models/device.rs` | Created | `DeviceInfo` struct and `DeviceMode` enum (Normal, Recovery, DFU, kDFU, pwnDFU) |
| `src-tauri/src/commands/mod.rs` | Created | Module declaration for `device` |
| `src-tauri/src/commands/device.rs` | Created | `detect_device` command — parses `ideviceinfo` output, falls back to `irecovery -q` for Recovery/DFU |
| `src-tauri/src/lib.rs` | Modified | Registered `tauri-plugin-log`, added `detect_device` command, declared `error`, `models`, `commands` modules |

#### Frontend Cleanup
| File | Action | Description |
|------|--------|-------------|
| `src/lib/components/device/DeviceStatus.svelte` | Modified | Converted from Svelte 4 (`export let`, `$:`) to Svelte 5 runes (`$props()`, `$derived()`) |
| `src/lib/Counter.svelte` | Deleted | Removed unused Tauri template scaffold file |

### Phase 2: Device Detection & Core UI (100% Complete)

#### Stores
| File | Action | Description |
|------|--------|-------------|
| `src/lib/stores/navigationStore.svelte.ts` | Created | `ViewName` type (9 views) + `NavigationStore` class with `navigate()`, `goBack()` |
| `src/lib/stores/settingsStore.svelte.ts` | Created | Theme, terminal visibility, terminal height, auto-detect, poll interval settings |
| `src/lib/stores/deviceStore.svelte.ts` | Modified | Enriched with full fields (ecid, serial, model, product_type, ios_version, mode) + `updateFromBackend()` |

#### Views
| File | Action | Description |
|------|--------|-------------|
| `src/lib/views/HomeView.svelte` | Created | Welcome page with device summary card and quick action navigation grid |
| `src/lib/views/RestoreView.svelte` | Created | Placeholder — Custom IPSW restore, tethered/OTA downgrade, powdersn0w |
| `src/lib/views/JailbreakView.svelte` | Created | Placeholder — checkm8, g1lbertJB, evasi0n, untethered jailbreak |
| `src/lib/views/SHSHView.svelte` | Created | Placeholder — tsschecker, onboard blob dump, Cydia server blobs |
| `src/lib/views/SSHRamdiskView.svelte` | Created | Placeholder — SSH ramdisk boot, file system access, activation bypass |
| `src/lib/views/AppsView.svelte` | Created | Placeholder — IPA install, app dump, TrollStore |
| `src/lib/views/DataView.svelte` | Created | Placeholder — Backup, restore, mount filesystem, erase device |
| `src/lib/views/UtilitiesView.svelte` | Created | Placeholder — Recovery mode, activation, syslog, diagnostics |
| `src/lib/views/SettingsView.svelte` | Created | **Functional** — Theme selector, terminal toggle, poll interval, about section |

#### Navigation Wiring
| File | Action | Description |
|------|--------|-------------|
| `src/lib/components/layout/Sidebar.svelte` | Modified | Replaced local `currentView` state with `navigationStore`; calls `navigationStore.navigate()` |
| `src/lib/components/layout/ContentArea.svelte` | Modified | Renders correct view component based on `navigationStore.currentView` |
| `src/App.svelte` | Modified | Uses `deviceStore.updateFromBackend()` with `detect_device` results; polls with `settingsStore.pollIntervalMs` |

---

## Remaining Tasks

### Phase 3: Restore & Downgrade
- [ ] Restore option determination logic (which restore method based on device + target iOS)
- [ ] IPSW download manager with aria2c
- [ ] IPSW verification (SHA-1 checksums)
- [ ] RestoreView wizard UI (step-by-step flow)
- [ ] futurerestore wrapper (Rust tool wrapper)
- [ ] idevicerestore wrapper (Rust tool wrapper)
- [ ] Restore preparation pipeline (IPSW extraction, patching, signing)
- [ ] powdersn0w restore flow

### Phase 4: Jailbreak & SSH Ramdisk
- [ ] gaster/checkm8 exploit wrapper
- [ ] SSH ramdisk boot logic (iBSS/iBEC patching, ramdisk creation)
- [ ] JailbreakView functional UI
- [ ] SSHRamdiskView functional UI
- [ ] DFU Helper visual guide component
- [ ] kloader wrapper for tethered boot
- [ ] pwned iBSS/iBEC logic
- [ ] g1lbertJB integration
- [ ] evasi0n untether integration

### Phase 5: SHSH Blob Management
- [ ] tsschecker wrapper
- [ ] Onboard blob dumping (via SSH ramdisk)
- [ ] SHSHView functional UI
- [ ] Cydia server blob fetching
- [ ] Blob storage and organization

### Phase 6: App & Data Management
- [ ] IPA install via ideviceinstaller
- [ ] App dump via clutch
- [ ] AppsView functional UI
- [ ] Backup/restore via idevicebackup2
- [ ] DataView functional UI
- [ ] Filesystem mount/erase operations

### Phase 7: Utilities & Polish
- [ ] UtilitiesView functional UI (enter/exit recovery, activation, syslog, diagnostics)
- [ ] TrollStore installation flow
- [ ] Global error handling and toast notifications
- [ ] Update checker
- [ ] UI polish pass (animations, transitions, responsive adjustments)
- [ ] Platform-specific testing (macOS + Linux)
- [ ] Common UI components (Button, Select, Modal, Toast, ProgressBar, FilePickerButton, ConfirmDialog)
- [ ] Wizard components (Container, Step, Progress)

### Phase 8: Packaging & Distribution (Partially Done)
- [x] Tauri bundler config (.dmg, .deb/.AppImage)
- [x] Sidecar binary bundling
- [x] Resource bundling
- [x] CI/CD pipeline (GitHub Actions)
- [ ] Linux ARM64 CI/CD target
- [ ] User documentation
- [ ] Migration guide from bash script

### Backend Infrastructure (Ongoing)
- [ ] `state.rs` — Global app state management
- [ ] Tool wrappers in `tools/` — idevice, irecovery, futurerestore, gaster, powdersn0w, img4, tsschecker, ssh, ipsw_tool
- [ ] Service modules — device_detection, firmware_keys, download, dependency
- [ ] Additional command modules — restore, jailbreak, shsh, ramdisk, ipsw, apps, data, utilities
- [ ] API wrapper layer (`src/lib/api/`) — Typed Tauri invoke wrappers
- [ ] Utility modules (`src/lib/utils/`) — Formatting, platform detection

---

## Build Status
- **Frontend (Vite/Svelte):** ✅ Compiles cleanly
- **Backend (Rust/Tauri):** ✅ Compiles cleanly (`cargo check` passes)