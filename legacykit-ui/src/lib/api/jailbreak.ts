import { invoke } from '@tauri-apps/api/core';

export type GasterAction = 'pwn' | 'reset';

export interface GasterRequest {
  action: GasterAction;
}

export interface GasterResult {
  action: GasterAction;
  binary: string;
  args: string[];
}

export function runGaster(request: GasterRequest): Promise<GasterResult> {
  return invoke<GasterResult>('run_gaster', { request });
}

export interface KloaderRequest {
  ibssPath: string;
  ibecPath: string | null;
}

export interface KloaderResult {
  binary: string;
  args: string[];
}

export function runKloader(request: KloaderRequest): Promise<KloaderResult> {
  return invoke<KloaderResult>('run_kloader', { request });
}

export interface UntetherRequest {
  extraArgs: string[];
}

export interface UntetherResult {
  binary: string;
  args: string[];
}

export function runG1lbertJB(request: UntetherRequest): Promise<UntetherResult> {
  return invoke<UntetherResult>('run_g1lbertjb', { request });
}

export function runEvasi0n(request: UntetherRequest): Promise<UntetherResult> {
  return invoke<UntetherResult>('run_evasi0n', { request });
}
