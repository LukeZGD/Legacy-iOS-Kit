import { invoke } from '@tauri-apps/api/core';

export type AppListScope = 'user' | 'system' | 'all';

export interface ListAppsRequest {
  scope: AppListScope;
}

export interface InstalledApp {
  bundleId: string;
  displayName: string | null;
  version: string | null;
}

export interface ListAppsResult {
  scope: AppListScope;
  apps: InstalledApp[];
}

export interface InstallIpaRequest {
  ipaPaths: string[];
}

export interface InstallIpaResult {
  installed: string[];
}

export interface UninstallAppRequest {
  bundleId: string;
}

export interface UninstallAppResult {
  bundleId: string;
}

export function listInstalledApps(request: ListAppsRequest): Promise<ListAppsResult> {
  return invoke<ListAppsResult>('list_installed_apps', { request });
}

export function installIpa(request: InstallIpaRequest): Promise<InstallIpaResult> {
  return invoke<InstallIpaResult>('install_ipa', { request });
}

export function uninstallApp(request: UninstallAppRequest): Promise<UninstallAppResult> {
  return invoke<UninstallAppResult>('uninstall_app', { request });
}
