import { invoke } from '@tauri-apps/api/core';

export interface BackupCreateRequest {
  backupRoot: string;
  udid: string | null;
  full: boolean;
}

export interface BackupCreateResult {
  backupPath: string;
  args: string[];
}

export interface BackupRestoreRequest {
  backupPath: string;
  udid: string | null;
  system: boolean;
  settings: boolean;
  reboot: boolean;
}

export interface BackupRestoreResult {
  backupPath: string;
  args: string[];
}

export interface EraseDeviceRequest {
  udid: string | null;
  confirmation: string;
}

export interface EraseDeviceResult {
  args: string[];
}

export type BackupEncryptionAction = 'on' | 'off' | 'changePassword';

export interface BackupEncryptionRequest {
  action: BackupEncryptionAction;
  udid: string | null;
}

export interface BackupEncryptionResult {
  action: BackupEncryptionAction;
  args: string[];
}

export interface ListBackupsRequest {
  backupRoot: string;
}

export interface BackupEntry {
  path: string;
  name: string;
  sizeBytes: number;
  modifiedUnix: number | null;
}

export interface ListBackupsResult {
  backupRoot: string;
  backups: BackupEntry[];
}

export const ERASE_CONFIRMATION = 'Yes, do as I say';

export function createBackup(request: BackupCreateRequest): Promise<BackupCreateResult> {
  return invoke<BackupCreateResult>('create_backup', { request });
}

export function restoreBackup(request: BackupRestoreRequest): Promise<BackupRestoreResult> {
  return invoke<BackupRestoreResult>('restore_backup', { request });
}

export function eraseDevice(request: EraseDeviceRequest): Promise<EraseDeviceResult> {
  return invoke<EraseDeviceResult>('erase_device', { request });
}

export function setBackupEncryption(
  request: BackupEncryptionRequest,
): Promise<BackupEncryptionResult> {
  return invoke<BackupEncryptionResult>('set_backup_encryption', { request });
}

export function listBackups(request: ListBackupsRequest): Promise<ListBackupsResult> {
  return invoke<ListBackupsResult>('list_backups', { request });
}
