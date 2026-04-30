import { invoke } from '@tauri-apps/api/core';

export interface IpswExtractRequest {
  ipswPath: string;
  componentPath: string;
  outputPath: string;
}

export interface IpswExtractResult {
  outputPath: string;
  bytes: number;
}

export type IbootBitWidth = 'bits32' | 'bits64';

export interface IbootPatchRequest {
  inputPath: string;
  outputPath: string;
  bitWidth: IbootBitWidth;
  bootArgs: string | null;
  bypassRsa: boolean;
  debug: boolean;
}

export interface IbootPatchResult {
  outputPath: string;
  binary: string;
  args: string[];
}

export interface Img4PackRequest {
  im4pPath: string;
  outputPath: string;
  shshPath: string | null;
  im4mPath: string | null;
}

export interface Img4PackResult {
  outputPath: string;
  binary: string;
  args: string[];
}

export interface Img3RepackRequest {
  inputPath: string;
  outputPath: string;
  templatePath: string | null;
  key: string | null;
  iv: string | null;
}

export interface Img3RepackResult {
  outputPath: string;
  binary: string;
  args: string[];
}

export interface KernelPatchRequest {
  inputPath: string;
  outputPath: string;
  bitWidth: IbootBitWidth;
  flags: string[];
}

export interface KernelPatchResult {
  outputPath: string;
  binary: string;
  args: string[];
}

export function extractIpswComponent(request: IpswExtractRequest): Promise<IpswExtractResult> {
  return invoke<IpswExtractResult>('extract_ipsw_component', { request });
}

export function patchIboot(request: IbootPatchRequest): Promise<IbootPatchResult> {
  return invoke<IbootPatchResult>('patch_iboot', { request });
}

export function packImg4(request: Img4PackRequest): Promise<Img4PackResult> {
  return invoke<Img4PackResult>('pack_img4', { request });
}

export function repackImg3(request: Img3RepackRequest): Promise<Img3RepackResult> {
  return invoke<Img3RepackResult>('repack_img3', { request });
}

export function patchKernel(request: KernelPatchRequest): Promise<KernelPatchResult> {
  return invoke<KernelPatchResult>('patch_kernel', { request });
}

export type RamdiskAction = 'add' | 'remove' | 'resize';

export interface RamdiskModifyRequest {
  ramdiskPath: string;
  action: RamdiskAction;
  sourcePath: string | null;
  targetPath: string | null;
  sizeMb: number | null;
}

export interface RamdiskModifyResult {
  ramdiskPath: string;
  binary: string;
  args: string[];
}

export function modifyRamdisk(request: RamdiskModifyRequest): Promise<RamdiskModifyResult> {
  return invoke<RamdiskModifyResult>('modify_ramdisk', { request });
}
