import { invoke } from '@tauri-apps/api/core';
import type { DeviceInfo } from '$lib/stores/deviceStore.svelte';

export type RestoreOptionKind =
  | 'otaDowngrade'
  | 'powdersnow'
  | 'latest'
  | 'blobRestore'
  | 'tethered'
  | 'customIpsw'
  | 'dfuIpsw'
  | 'setNonce'
  | 'ipswDownloader'
  | 'moreVersions';

export interface RestoreOption {
  kind: RestoreOptionKind;
  title: string;
  description: string;
  targetVersion: string | null;
  requiresBlobs: boolean;
  requiresDfu: boolean;
}

export interface RestoreOptionsResponse {
  productType: string | null;
  processorGeneration: number | null;
  options: RestoreOption[];
  warnings: string[];
}

export interface IpswDownloadRequest {
  url: string;
  outputDir: string;
  fileName: string | null;
}

export interface IpswDownloadResult {
  path: string;
}

export interface IpswVerifyRequest {
  path: string;
  expectedSha1: string | null;
}

export interface IpswVerifyResult {
  path: string;
  calculatedSha1: string;
  expectedSha1: string | null;
  matches: boolean | null;
}

export type RestoreTool = 'ideviceRestore' | 'futureRestore';

export interface RestoreRunRequest {
  tool: RestoreTool;
  ipswPath: string;
  shshPath: string | null;
  erase: boolean;
  update: boolean;
  usePwndfu: boolean;
  skipBlob: boolean;
  setNonce: boolean;
  noBaseband: boolean;
  latestSep: boolean;
  latestBaseband: boolean;
  dryRun: boolean;
}

export interface RestoreCommandPreview {
  supported: boolean;
  tool: RestoreTool;
  binary: string;
  args: string[];
  warnings: string[];
}

export function getRestoreOptions(device: DeviceInfo): Promise<RestoreOptionsResponse> {
  return invoke<RestoreOptionsResponse>('get_restore_options', { device });
}

export function downloadIpsw(request: IpswDownloadRequest): Promise<IpswDownloadResult> {
  return invoke<IpswDownloadResult>('download_ipsw', { request });
}

export function verifyIpsw(request: IpswVerifyRequest): Promise<IpswVerifyResult> {
  return invoke<IpswVerifyResult>('verify_ipsw', { request });
}

export function previewRestoreCommand(request: RestoreRunRequest): Promise<RestoreCommandPreview> {
  return invoke<RestoreCommandPreview>('preview_restore_command', { request });
}

export function startRestore(request: RestoreRunRequest): Promise<RestoreCommandPreview> {
  return invoke<RestoreCommandPreview>('start_restore', { request });
}
