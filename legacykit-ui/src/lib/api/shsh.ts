import { invoke } from '@tauri-apps/api/core';

export interface SaveShshRequest {
  deviceType: string;
  deviceEcid: string;
  boardConfig: string | null;
  iosVersion: string;
  buildId: string | null;
  buildManifestPath: string | null;
  apnonce: string | null;
  generator: string | null;
  outputDir: string;
}

export interface SaveShshResult {
  blobPaths: string[];
  args: string[];
}

export interface CydiaBlobRequest {
  deviceType: string;
  deviceEcid: string;
  buildIds: string[];
  outputDir: string;
}

export interface CydiaBlobAttempt {
  buildId: string;
  saved: boolean;
  blobPath: string | null;
  message: string | null;
}

export interface CydiaBlobResult {
  attempts: CydiaBlobAttempt[];
}

export interface DumpOnboardBlobRequest {
  rawDumpPath: string;
  outputPath: string;
}

export interface DumpOnboardBlobResult {
  blobPath: string;
  args: string[];
}

export interface ListBlobsRequest {
  directory: string;
}

export interface SavedBlob {
  path: string;
  fileName: string;
  sizeBytes: number;
  modifiedUnix: number | null;
  deviceType: string | null;
  deviceEcid: string | null;
  iosVersion: string | null;
  buildId: string | null;
}

export interface ListBlobsResult {
  directory: string;
  blobs: SavedBlob[];
}

export function saveShshBlob(request: SaveShshRequest): Promise<SaveShshResult> {
  return invoke<SaveShshResult>('save_shsh_blob', { request });
}

export function fetchCydiaBlobs(request: CydiaBlobRequest): Promise<CydiaBlobResult> {
  return invoke<CydiaBlobResult>('fetch_cydia_blobs', { request });
}

export function dumpOnboardBlob(
  request: DumpOnboardBlobRequest,
): Promise<DumpOnboardBlobResult> {
  return invoke<DumpOnboardBlobResult>('dump_onboard_blob', { request });
}

export function listSavedBlobs(request: ListBlobsRequest): Promise<ListBlobsResult> {
  return invoke<ListBlobsResult>('list_saved_blobs', { request });
}
